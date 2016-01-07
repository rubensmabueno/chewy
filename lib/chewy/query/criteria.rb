require 'chewy/query/compose'

module Chewy
  class Query
    class Criteria
      include Compose
      ARRAY_STORAGES = [:queries, :filters, :post_filters, :sort, :fields, :types, :scores]
      HASH_STORAGES = [:options, :request_options, :facets, :aggregations, :suggest, :script_fields]
      STORAGES = ARRAY_STORAGES + HASH_STORAGES

      def initialize(options = {})
        @options = options.merge(
          query_mode: Chewy.query_mode,
          filter_mode: Chewy.filter_mode,
          post_filter_mode: Chewy.post_filter_mode || Chewy.filter_mode
        )
      end

      def ==(other)
        other.is_a?(self.class) && storages == other.storages
      end

      { ARRAY_STORAGES => '[]', HASH_STORAGES => '{}' }.each do |storages, default|
        storages.each do |storage|
          class_eval <<-METHODS, __FILE__, __LINE__ + 1
            def #{storage}
              @#{storage} ||= #{default}
            end
          METHODS
        end
      end

      STORAGES.each do |storage|
        define_method "#{storage}?" do
          send(storage).any?
        end
      end

      def none?
        !!options[:none]
      end

      def update_options(modifier)
        options.merge!(modifier)
      end

      def update_request_options(modifier)
        request_options.merge!(modifier)
      end

      def update_facets(modifier)
        facets.merge!(modifier)
      end

      def update_scores(modifier)
        @scores = scores + Array.wrap(modifier).reject(&:blank?)
      end

      def update_aggregations(modifier)
        aggregations.merge!(modifier)
      end

      def update_suggest(modifier)
        suggest.merge!(modifier)
      end

      def update_script_fields(modifier)
        script_fields.merge!(modifier)
      end

      [:filters, :queries, :post_filters].each do |storage|
        class_eval <<-RUBY
          def update_#{storage}(modifier)
            @#{storage} = #{storage} + Array.wrap(modifier).reject(&:blank?)
          end
        RUBY
      end

      def update_sort(modifier, options = {})
        @sort = nil if options[:purge]
        modifier = Array.wrap(modifier).flatten.map do |element|
          element.is_a?(Hash) ? element.map { |k, v| { k => v } } : element
        end.flatten
        @sort = sort + modifier
      end

      %w(fields types).each do |storage|
        define_method "update_#{storage}" do |modifier, options = {}|
          variable = "@#{storage}"
          instance_variable_set(variable, nil) if options[:purge]
          modifier = send(storage) | Array.wrap(modifier).flatten.map(&:to_s).reject(&:blank?)
          instance_variable_set(variable, modifier)
        end
      end

      def merge!(other)
        STORAGES.each do |storage|
          send("update_#{storage}", other.send(storage))
        end
        self
      end

      def merge(other)
        clone.merge!(other)
      end

      def request_body
        body = _filtered_query(_request_query, _request_filter, options.slice(:strategy))

        if options[:simple]
          { body: body.presence || { query: { match_all: {} } } }
        else
          body.merge!(post_filter: _request_post_filter) if post_filters?
          body.merge!(facets: facets) if facets?
          body.merge!(aggregations: aggregations) if aggregations?
          body.merge!(suggest: suggest) if suggest?
          body.merge!(sort: sort) if sort?
          body.merge!(_source: fields) if fields?
          body.merge!(script_fields: script_fields) if script_fields?

          body = _boost_query(body)

          { body: body.merge!(request_options) }
        end
      end

      protected

      def storages
        STORAGES.map { |storage| send(storage) }
      end

      def initialize_clone(other)
        STORAGES.each do |storage|
          value = other.send(storage)
          instance_variable_set("@#{storage}", value.deep_dup)
        end
      end

      def _boost_query(body)
        return body unless scores?
        query = body.delete :query
        filter = body.delete :filter
        if query && filter
          query = { filtered: { query: query, filter: filter } }
          filter = nil
        end
        score = {}
        score[:functions] = scores
        score[:boost_mode] = options[:boost_mode] if options[:boost_mode]
        score[:score_mode] = options[:score_mode] if options[:score_mode]
        score[:query] = query if query
        score[:filter] = filter if filter
        body.tap { |b| b[:query] = { function_score: score } }
      end

      def _request_query
        _queries_join(queries, options[:query_mode])
      end

      def _request_filter
        filter_mode = options[:filter_mode]
        request_filter = if filter_mode == :and
                           filters
                         else
                           [_filters_join(filters, filter_mode)]
                         end

        _filters_join([_request_types, *request_filter], :and)
      end

      def _request_types
        _filters_join(types.map { |type| { type: { value: type } } }, :or)
      end

      def _request_post_filter
        _filters_join(post_filters, options[:post_filter_mode])
      end
    end
  end
end
