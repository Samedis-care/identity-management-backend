module DevelopmentJsonApiController

  extend ActiveSupport::Concern

  def self.included(base)
    base.class_eval do
      alias_method :_prod_records_index_paged, :records_index_paged
      alias_method :records_index_paged, :_dev_records_index_paged

      alias_method :_prod_record_show, :record_show
      alias_method :record_show, :_dev_record_show

    end
  end

  # Only in development environment
  # Will call explain on the index action data determination
  # and alert if any COLLSCAN has occured
  def _dev_records_index_paged
    _explain = _prod_records_index_paged.explain rescue {}
    if _explain.dig(:queryPlanner, :winningPlan).to_json.include?('COLLSCAN')
      puts "=" * 80
      puts "WARNING: INDEX COLLSCAN DETECTED! #{self.class}"
      puts "-" * 80
      puts caller[0]
      puts "-" * 80
      pp _explain
      puts "=" * 80
      Sentry.add_breadcrumb(Sentry::Breadcrumb.new(
        category: "db",
        message: "column scan detected",
        level: "warn",
        data: _explain
      ))
      Sentry.capture_message("column scan on #{request.fullpath}")
      #debugger
    end
    _prod_records_index_paged
  end

  def _dev_record_show
    _explain = _prod_record_show.explain rescue {}
    if _explain.dig(:queryPlanner, :winningPlan).to_json.include?('COLLSCAN')
      puts "=" * 80
      puts "WARNING: SHOW COLLSCAN DETECTED! #{self.class}"
      puts "-" * 80
      puts caller[0]
      puts "-" * 80
      pp _explain
      puts "=" * 80
      #debugger
      Sentry.add_breadcrumb(Sentry::Breadcrumb.new(
        category: "db",
        message: "column scan detected",
        level: "warn",
        data: _explain
      ))
      Sentry.capture_message("column scan on #{request.fullpath}")
    end
    _prod_record_show
  end

end
