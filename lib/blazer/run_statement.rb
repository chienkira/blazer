module Blazer
  class RunStatement
    def perform(data_source, statement, options = {})
      query = options[:query]
      Blazer.transform_statement.call(data_source, statement) if Blazer.transform_statement

      # audit
      if Blazer.audit
        audit = Blazer::Audit.new(statement: statement)
        audit.query = query
        audit.data_source = data_source.id
        audit.user = options[:user]
        audit.save!
      end

      start_time = Time.now

      # remove the ;
      statement = statement.gsub ';', ' '

      # pagination
      pager_limit = 10000    # maximum: 10,000
      pager_query_result = data_source.run_statement("select count(*) as count from ( #{statement} ) as temp_table", options)

      # add LIMIT if it is not presented
      unless statement.match(/.*LIMIT +\d+;?\s*$/i)
        statement = "#{statement} LIMIT #{pager_limit}"
      end

      result = data_source.run_statement(statement, options)
      duration = Time.now - start_time

      if Blazer.audit
        audit.duration = duration if audit.respond_to?(:duration=)
        audit.error = result.error if audit.respond_to?(:error=)
        audit.timed_out = result.timed_out? if audit.respond_to?(:timed_out=)
        audit.cached = result.cached? if audit.respond_to?(:cached=)
        if !result.cached? && duration >= 10
          audit.cost = data_source.cost(statement) if audit.respond_to?(:cost=)
        end
        audit.save! if audit.changed?
      end

      if query && !result.timed_out? && !query.variables.any?
        query.checks.each do |check|
          check.update_state(result)
        end
      end

      if pager_query_result.rows.present? and pager_query_result.rows[0].present?
        result.pager[:maximum] = pager_limit
        result.pager[:total_count] = pager_query_result.rows[0][0]
        result.pager[:page_count] = (pager_query_result.rows[0][0] - 1)/pager_limit + 1
      end

      result
    end
  end
end
