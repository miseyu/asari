require_relative "../asari_spec_helper"
require 'cgi'

describe Asari do
  let(:url_base) { "http://search-testdomain.us-east-1.cloudsearch.amazonaws.com" }

  before :each do
    @asari = Asari.new("testdomain")
    stub_const("HTTParty", double())
    HTTParty.stub(:get).and_return(fake_response)
  end

  describe "searching" do
    shared_examples_for 'code that does basic searches' do
      before(:each) {ENV['CLOUDSEARCH_API_VERSION'] = api_version}
      after(:each) {ENV['CLOUDSEARCH_API_VERSION'] = '2011-02-01'}
      context "when region is not specified" do
        it "allows you to search using default region." do
          query = 'testsearch&size=10'
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}")
          @asari.search("testsearch")
        end
      end

      context "when region is not specified" do
        let(:url_base){ "http://search-testdomain.my-region.cloudsearch.amazonaws.com" }
        before(:each) do
          @asari.aws_region = 'my-region'
        end
        it "allows you to search using specified region." do
          query = 'testsearch&size=10'
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}")
          @asari.search("testsearch")
        end
      end

      it "escapes dangerous characters in search terms." do
        query = 'testsearch%21&size=10'
        HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}")
        @asari.search("testsearch!")
      end

      it "honors the page_size option" do
        query = 'testsearch&size=20'
        HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}")
        @asari.search("testsearch", :page_size => 20)
      end

      it "honors the page option" do
        query = 'testsearch&size=20&start=40'
        HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}")
        @asari.search("testsearch", :page_size => 20, :page => 3)
      end

    end

    context 'the 2011-02-01 api' do
      let(:api_version) { "2011-02-01" }
      it_behaves_like 'code that does basic searches'

      describe "boolean searching" do
        it "builds a query string from a passed hash" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=&bq=%28and+foo%3A%27bar%27+baz%3A%27bug%27%29&size=10")
          @asari.search(filter: { and: { foo: "bar", baz: "bug" }})
        end

        it "honors the logic types" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=&bq=%28or+foo%3A%27bar%27+baz%3A%27bug%27%29&size=10")
          @asari.search(filter: { or: { foo: "bar", baz: "bug" }})
        end

        it "supports nested logic" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=&bq=%28or+is_donut%3A%27true%27%28and+round%3A%27true%27+frosting%3A%27true%27+fried%3A%27true%27%29%29&size=10")
          @asari.search(filter: { or: { is_donut: true, and:
                                        { round: true, frosting: true, fried: true }}
          })
        end

        it "fails gracefully with empty params" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=&bq=%28or+is_donut%3A%27true%27%29&size=10")
          @asari.search(filter: { or: { is_donut: true, and:
                                        { round: "", frosting: nil, fried: nil }}
          })
        end

        it "supports full text search and boolean searching" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=nom&bq=%28or+is_donut%3A%27true%27%28and+fried%3A%27true%27%29%29&size=10")
          @asari.search("nom", filter: { or: { is_donut: true, and:
                                               { round: "", frosting: nil, fried: true }}
          })
        end
      end

      describe "the rank option" do
        it "takes a plain string" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&rank=some_field")
          @asari.search("testsearch", :rank => "some_field")
        end

        it "takes an array with :asc" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&rank=some_field")
          @asari.search("testsearch", :rank => ["some_field", :asc])
        end

        it "takes an array with :desc" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&rank=-some_field")
          @asari.search("testsearch", :rank => ["some_field", :desc])
        end
      end
    end

    context 'the 2013-01-01 api' do
      let(:api_version) { "2013-01-01" }
      let(:options) { "&q.parser=structured&size=10" }
      it_behaves_like 'code that does basic searches'
      before(:each) {ENV['CLOUDSEARCH_API_VERSION'] = api_version}
      after(:each) {ENV['CLOUDSEARCH_API_VERSION'] = '2011-02-01'}

      describe 'boolean searching,  structured queries' do
        it "builds a query string from a passed hash" do
          query = CGI.escape("(and foo:'bar' baz:'bug')")
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}#{options}")
          @asari.search(filter: { and: { foo: "bar", baz: "bug" }})
        end

        it "honors the logic types" do
          query = CGI.escape("(or foo:'bar' baz:'bug')")
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}#{options}")
          @asari.search(filter: { or: { foo: "bar", baz: "bug" }})
        end

        it "supports nested logic" do
          query = CGI.escape("(or is_donut:'true'(and round:'true' frosting:'true' fried:'true'))")
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}#{options}")
          @asari.search(filter: { or: { is_donut: true, and:
                                        { round: true, frosting: true, fried: true }}
          })
        end

        it "fails gracefully with empty params" do
          query = CGI.escape("(or is_donut:'true')")
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}#{options}")
          @asari.search(filter: { or: { is_donut: true, and:
                                        { round: "", frosting: nil, fried: nil }}
          })
        end

        it "does full text search when filter option is used" do
          query = CGI.escape("(and 'nom' (or is_donut:'true'(and fried:'true')))")
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=#{query}#{options}")
          @asari.search("nom", filter: { or: { is_donut: true, and:
                                               { round: "", frosting: nil, fried: true }}
          })
        end
      end

      describe "the rank option" do
        it "takes a plain string" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&sort=some_field+asc")
          @asari.search("testsearch", :rank => "some_field")
        end

        it "takes an array with :asc" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&sort=some_field+asc")
          @asari.search("testsearch", :rank => ["some_field", :asc])
        end

        it "takes an array with :desc" do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&sort=some_field+desc")
          @asari.search("testsearch", :rank => ["some_field", :desc])
        end
      end
    end


    it "returns a list of document IDs for search results." do
      result = @asari.search("testsearch")

      expect(result.size).to eq(2)
      expect(result[0]).to eq("123")
      expect(result[1]).to eq("456")
      expect(result.total_pages).to eq(1)
      expect(result.current_page).to eq(1)
      expect(result.page_size).to eq(10)
      expect(result.total_entries).to eq(2)
    end

    it "returns an empty list when no search results are found." do
      HTTParty.stub(:get).and_return(fake_empty_response)
      result = @asari.search("testsearch")
      expect(result.size).to eq(0)
      expect(result.total_pages).to eq(1)
      expect(result.current_page).to eq(1)
      expect(result.total_entries).to eq(0)
    end

    context 'return_fields option' do
      let(:return_struct) {{"123" => {"name" => "Beavis", "address" => "arizona"},
                            "456" => {"name" => "Honey Badger", "address" => "africa"}}}

      context '2011-02-01 api' do
        let(:api_version) { "2011-02-01" }
        let(:response_with_field_data) {  OpenStruct.new(:parsed_response => { "hits" => {
          "found" => 2,
          "start" => 0,
          "hit" => [{"id" => "123",
                     "data" => {"name" => "Beavis", "address" => "arizona"}},
          {"id" => "456",
           "data" => {"name" => "Honey Badger", "address" => "africa"}}]}},
        :response => OpenStruct.new(:code => "200"))
        }
        before :each do
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&return-fields=name,address").and_return response_with_field_data
        end

        subject { @asari.search("testsearch", :return_fields => [:name, :address])}
        it {should eql return_struct}
      end

      context '2013-01-01 api' do
        let(:api_version) { "2013-01-01" }
        let(:response_with_field_data) {  OpenStruct.new(:parsed_response => { "hits" => {
          "found" => 2,
          "start" => 0,
          "hit" => [{"id" => "123",
                     "fields" => {"name" => "Beavis", "address" => "arizona"}},
          {"id" => "456",
           "fields" => {"name" => "Honey Badger", "address" => "africa"}}]}},
        :response => OpenStruct.new(:code => "200"))
        }
        before :each do
          ENV['CLOUDSEARCH_API_VERSION'] = '2013-01-01'
          HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=testsearch&size=10&return=name,address").and_return response_with_field_data
        end
        after(:each) {ENV['CLOUDSEARCH_API_VERSION'] = '2011-02-01'}

        subject { @asari.search("testsearch", :return_fields => [:name, :address])}
        it {should eql return_struct}
      end
    end

    it "raises an exception if the service errors out." do
      HTTParty.stub(:get).and_return(fake_error_response)
      expect { @asari.search("testsearch)") }.to raise_error Asari::SearchException
    end

    it "raises an exception if there are internet issues." do
      HTTParty.stub(:get).and_raise(SocketError.new)
      expect { @asari.search("testsearch)") }.to raise_error Asari::SearchException
    end

  end


  describe "geography searching" do
    let(:api_version) { "2011-02-01" }
    it "builds a proper query string" do
      HTTParty.should_receive(:get).with("#{url_base}/#{api_version}/search?q=&bq=%28and+lat%3A2505771415..2506771417+lng%3A2358260777..2359261578%29&size=10")
      @asari.search filter: { and: Asari::Geography.coordinate_box(meters: 5000, lat: 45.52, lng: 122.6819) }
    end
  end


  describe "protected methods" do
    let(:api_version) { '2011-02-01' }
    before(:each) { ENV['CLOUDSEARCH_API_VERSION'] = api_version }
    before do
      Asari.send(:public, *Asari.protected_instance_methods)
    end

    describe "#build_query" do
      let(:filter_options) do
        {:and =>
          { :field1 => "field1" }
        }
      end
      let(:options) { {} }
      let(:term) { "" }
      subject { @asari.build_query(term, options) }
      before { @asari.stub(:boolean_query).and_return("field1:field1") }

      context "for 2011-02-01 api_version" do
        it { should eql "?q=" }

        context "when filter options are specified" do
          let(:options) { { filter: filter_options } }
          it { should eql "?q=&bq=field1%3Afield1" }

          context "when term is specified" do
            let(:term) { 'search_term' }
            it { should eql "?q=search_term&bq=field1%3Afield1" }
          end
        end
      end

      context "for 2013-01-01 api_version" do
        let(:api_version) { '2013-01-01' }
        it { should eql "?q=" }

        context "when filter options are specified" do
          let(:options) { { filter: filter_options } }
          it { should eql "?q=field1%3Afield1&q.parser=structured" }

          context "when term is specified" do
            let(:term) { 'search_term' }
            it { should eql "?q=#{CGI.escape("(and 'search_term' field1:field1)")}&q.parser=structured" }
          end
        end
      end
    end

    describe "#page_options" do
      let(:options) { {} }
      subject { @asari.page_options(options) }
      it { should eql "" }

      context "when rank options are specified" do
        let(:options) { { page: "11" } }
        before { @asari.stub(:page_size_options).and_return(5) }
        it { should eql "&start=50" }
      end
    end

    describe "#page_size_options" do
      let(:options) { {} }
      subject { @asari.page_size_options(options) }
      it { should eql 10 }

      context "when rank options are specified" do
        let(:options) { { page_size: "11" } }

        it { should eql 11 }
      end
    end

    describe "#rank_options" do
      let(:options) { {} }
      subject { @asari.rank_options(options) }
      it { should eql "" }

      context "when rank options are specified" do
        let(:options) { { rank: ['field1', :asc] } }

        context "for 2011-02-01 api_version" do
          it { should eql "&rank=field1" }
        end

        context "for 2013-01-01 api_version" do
          let(:api_version) { '2013-01-01' }
          it { should eql "&sort=field1+asc" }
        end
      end
    end

    describe "#return_fields_options" do
      let(:options) { {} }
      subject { @asari.return_fields_options(options) }
      it { should eql "" }

      context "when fields options are specified" do
        let(:options) { { return_fields: ['field1', 'field2'] } }

        context "for 2011-02-01 api_version" do
          it { should eql "&return-fields=field1,field2" }
        end

        context "for 2013-01-01 api_version" do
          let(:api_version) { '2013-01-01' }
          it { should eql "&return=field1,field2" }
        end
      end
    end
  end
end