require 'aws-sdk-resources'
require 'ox'
require 'oj'

require "asari/version"

require "asari/collection"
require "asari/exceptions"
require "asari/geography"

require "httparty"

require "ostruct"
require "json"
require "cgi"

class Asari
  def self.mode
    @@mode
  end

  def self.mode=(mode)
    @@mode = mode
  end

  attr_writer :api_version
  attr_writer :search_domain
  attr_writer :aws_region

  def initialize(search_domain=nil, aws_region=nil)
    @search_domain = search_domain
    @aws_region = aws_region
  end

  # Public: returns the current search_domain, or raises a
  # MissingSearchDomainException.
  #
  def search_domain
    @search_domain || raise(MissingSearchDomainException.new)
  end

  # Public: returns the current api_version, or the sensible default of
  # "2011-02-01" (at the time of writing, the current version of the
  # CloudSearch API).
  #
  def api_version
    @api_version || ENV['CLOUDSEARCH_API_VERSION'] || "2013-01-01"
  end

  # Public: returns the current aws_region, or the sensible default of
  # "us-east-1."
  def aws_region
    @aws_region || "us-east-1"
  end

  # Public: Search for the specified term.
  #
  # Examples:
  #
  #     @asari.search(filter: { and: { type: 'donuts' }}) #=> ["13,"28","35","50"]
  #
  # Returns: An Asari::Collection containing all document IDs in the system that match the
  #   specified search term. If no results are found, an empty Asari::Collection is
  #   returned.
  #
  # Raises: SearchException if there's an issue communicating the request to
  #   the server.
  def search(options = {})
    return Asari::Collection.sandbox_fake if self.class.mode == :sandbox
    client = Aws::CloudSearchDomain::Client.new(endpoint: "http://search-#{search_domain}.#{aws_region}.cloudsearch.amazonaws.com")
    query_options = { query_parser: 'structured', query: boolean_query(options[:filter]) }

    query_options[:size] = options[:size].nil? ? 100 : options[:size].to_i

    if options[:page]
      query_options[:start] = (options[:page].to_i - 1) * query_options[:size]
    end

    query_options[:cursor] = options[:cursor] if options[:cursor]

    client.search(query_options)
  end

  # Public: Add an item to the index with the given ID.
  #
  #     id - the ID to associate with this document
  #     fields - a hash of the data to associate with this document. This
  #       needs to match the search fields defined in your CloudSearch domain.
  #
  # Examples:
  #
  #     @asari.update_item("4", { :name => "Party Pooper", :email => ..., ... }) #=> nil
  #
  # Returns: nil if the request is successful.
  #
  # Raises: DocumentUpdateException if there's an issue communicating the
  #   request to the server.
  #
  def add_item(id, fields)
    return nil if self.class.mode == :sandbox
    query = create_item_query id, fields
    doc_request query
  end

  # Public: Update an item in the index based on its document ID.
  #   Note: As of right now, this is the same method call in CloudSearch
  #   that's utilized for adding items. This method is here to provide a
  #   consistent interface in case that changes.
  #
  # Examples:
  #
  #     @asari.update_item("4", { :name => "Party Pooper", :email => ..., ... }) #=> nil
  #
  # Returns: nil if the request is successful.
  #
  # Raises: DocumentUpdateException if there's an issue communicating the
  #   request to the server.
  #
  def update_item(id, fields)
    add_item(id, fields)
  end

  # Public: Remove an item from the index based on its document ID.
  #
  # Examples:
  #
  #     @asari.search("fritters") #=> ["13","28"]
  #     @asari.remove_item("13") #=> nil
  #
  # Returns: nil if the request is successful (note that asking the index to
  #   delete an item that's not present in the index is still a successful
  #   request).
  # Raises: DocumentUpdateException if there's an issue communicating the
  #   request to the server.
  def remove_item(id)
    return nil if self.class.mode == :sandbox

    query = remove_item_query id
    doc_request query
  end

  # Internal: helper method: common logic for queries against the doc endpoint.
  #
  def doc_request(query)
    client = Aws::CloudSearchDomain::Client.new(endpoint: "http://doc-#{search_domain}.#{aws_region}.cloudsearch.amazonaws.com")
    client.upload_documents(query)
  end

  def create_item_query(id, fields)
    return nil if self.class.mode == :sandbox
    result = {}
    result[:type] = 'add'
    result[:id] = id
    fields.each do |k, v|
      next if k == :id
      fields[k] = convert_date_or_time(fields[k])
      fields[k] = "" if v.nil?
    end
    result[:fields] = fields
    { documents: [result].to_json, content_type: 'application/json' }
  end

  def remove_item_query(id)
    return nil if self.class.mode == :sandbox
    result = {}
    result[:type] = 'delete'
    result[:id] = id
    { documents: [result].to_json, content_type: 'application/json' }
  end

  protected

  # Private: Builds the query from a passed hash
  #
  #     terms - a hash of the search query. %w(and or not) are reserved hash keys
  #             that build the logic of the query
  def boolean_query(terms = {})
    reduce = lambda { |hash|
      hash.reduce("") do |memo, (key, value)|
        if %w(and or not).include?(key.to_s) && value.is_a?(Hash)
          sub_query = reduce.call(value)
          memo += "(#{key}#{sub_query})" unless sub_query.empty?
        else
          if value.is_a?(Integer)
            memo += " #{key}:#{value}"
          elsif value.is_a?(Range)
            if [Time, Date, DateTime].any? { |target| value.first.is_a?(target) }
              memo += " #{key}:['#{convert_date_or_time(value.first)}','#{convert_date_or_time(value.last)}']"
            else
              memo += " #{key}:[#{value.first},#{value.last}]"
            end
          elsif value.is_a?(String) && value =~ /\A\d*\.\.\d*\Z/
            memo += " #{key}:#{value}"
          elsif !value.to_s.empty?
            memo += " #{key}:'#{value.to_s}'"
          end
        end
        memo
      end
    }
    reduce.call(terms)
  end

  def normalize_rank(rank)
    rank = Array(rank)
    rank << :asc if rank.size < 2

    if api_version == '2013-01-01'
      "#{rank[0]} #{rank[1]}"
    else
      rank[1] == :desc ? "-#{rank[0]}" : rank[0]
    end
  end

  def convert_date_or_time(obj)
    return obj unless [Time, Date, DateTime].any? { |target| obj.is_a?(target) }
    obj.to_time.utc.strftime('%FT%H:%M:%SZ')
  end

end

Asari.mode = :sandbox # default to sandbox
