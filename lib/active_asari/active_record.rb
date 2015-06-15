module ActiveAsari
  module ActiveRecord

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def env_test?
        (ENV['RAILS_ENV'] == 'test' or ENV['RACK_ENV'] == 'test')
      end

      def active_asari_index(class_name, options = {})
        attr_accessor :id
        active_asari_index_array = ACTIVE_ASARI_CONFIG[class_name].symbolize_keys.keys
        attr_accessor *active_asari_index_array
        asari_index ActiveAsari.asari_domain_name(class_name),  active_asari_index_array, options if !env_test?
      end
    end
  end
end
