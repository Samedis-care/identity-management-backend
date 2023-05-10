class AutoSwaggerSpecGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  include Rails.application.routes.url_helpers
  delegate :url_helpers, to: 'Rails.application.routes'

  def create_swagger_spec_file
    # Template method
    # First argument is the name of the template
    # Second argument is where to create the resulting file.
    if controller.ancestors.include?(JsonApiController)
      template 'swagger_spec.rb', File.join('spec/integration', "#{destination_file}_spec.rb")
    else
      puts "Skipping: #{controller} as it is not a supported JsonApiController".white
    end
  end

  private

  def controller_swagger
    if controller.const_defined?(:SWAGGER) && controller::SWAGGER.is_a?(Hash)
      controller::SWAGGER
    else
      {}
    end
  end

  def tag
    controller_swagger.fetch(:tag, model_name(count: 2))
  end

  def describe_spec
    "Auto generated swagger spec for #{controller.name}"
  end

  # url helper to be used
  def named_url_index
    "#{file_name}_url"
  end

  # url helper to be used
  def named_url
    "#{file_name.singularize}_url"
  end

  # path helper to be used
  def named_path_index
    "#{file_name}_path"
  end

  # path helper to be used
  def named_path
    "#{file_name.singularize}_path"
  end

  def parser
    @parse ||= URI::Parser.new
  end

  def required_parts(route_name)
    required_parts_auto(route_name)
  end

  def required_parts_auto(route_name)
    _parts = [route_name, route_name.singularize, route_name.pluralize].compact.collect do |rn|
      route_reqs.dig(rn)&.map { |_part| [_part.to_sym, "{#{_part}}"] }&.to_h || []
    end.first || []
  end

  def api_path_index
    _req_parts = required_parts(file_name)
    _path = url_helpers.try(named_path_index, _req_parts)
    parser.unescape _path
  end

  def api_path
#debugger if file_name.eql? "v1_user_tenant_index"
    if url_helpers.respond_to? named_path
      _req_parts = required_parts(file_name.singularize)
      _path = url_helpers.try(named_path, _req_parts) rescue debugger
      parser.unescape _path
    elsif url_helpers.respond_to? named_path_index
      api_path_index
    end
  end

  def schema(action)
    {
      schema_index:,
      schema_create:,
      schema_show:,
      schema_update:,
      schema_destroy:
    }["schema_#{action}".to_sym]
  end

  def schema_index
    controller::SCHEMA_ACTION[:index] || "overview_serializer::Schema.new.swagger_schema single: false, meta: true, links: true"
  end

  def schema_show
    controller::SCHEMA_ACTION[:show] || "serializer::Schema.new.swagger_schema single: true, meta: true, links: true"
  end

  def schema_create
    controller::SCHEMA_ACTION[:create] || schema_show
  end

  def schema_update
    controller::SCHEMA_ACTION[:update] || schema_show
  end

  def schema_destroy
    controller::SCHEMA_ACTION[:destroy] || schema_show
  end

  def route_reqs
    @route_reqs ||= Rails.application.routes.set.reject { |r| r.name.blank? }.map do |r|
      [r.name, r.required_parts]
    end.sort.to_h.with_indifferent_access
  end

  def route_set
    @route_set ||= Rails.application.routes.set.reject { |r| r.name.blank? }.map do |r|
      [r.name, r.defaults]
    end.sort.to_h.with_indifferent_access
  end

  def destination_file
    @destination_file ||= begin
      _route = route_set.dig(file_name)
      _path = _route.dig(:controller)
      raise "failed to detect path for: #{file_name}" if _path.blank?
      unless %i(index show create update destroy).include?(_route.dig(:action).to_sym)
        _path = "#{_path}##{_route.dig(:action)}"
      end
      _path
    end
    @destination_file
  end

  def path
    @path ||= begin
      _route = route_set.dig(file_name)
      _path = _route.dig(:controller)
      raise "failed to detect path for: #{file_name}" if _path.blank?
      _path
    end
    @path
  end

  def controller
    @controller ||= [path, :controller].join('_').camelize.constantize
    @controller::SCHEMA_ACTION ||= {}
    @controller::MODEL_BASE_ACTION ||= {}
    @controller::PERMIT_CREATE ||= []
    @controller::PERMIT_UPDATE ||= []
    @controller
  end

  def api_version
    controller.name.split('::')[1].downcase
  end

  def model
    raise "#{controller.name}::MODEL_BASE not defined" if controller::MODEL_BASE.nil?
    controller::MODEL_BASE
  end

  def model_action(action)
    controller::MODEL_BASE_ACTION[action] || model
  end

  def resource_name_index
    (controller::RESOURCE_NAME[:index] rescue nil) ||
      resource_plural
  end
  def resource_name_show
    (controller::RESOURCE_NAME[:show] rescue nil) ||
      resource_singular
  end
  def resource_name_create
    (controller::RESOURCE_NAME[:create] rescue nil) ||
      resource_singular
  end
  def resource_name_update
    (controller::RESOURCE_NAME[:update] rescue nil) ||
      resource_singular
  end
  def resource_name_destroy
    (controller::RESOURCE_NAME[:destroy] rescue nil) ||
      resource_singular
  end

  def attributes(action)
    {
      create: controller.try(:permitted_attributes_for_create) || permitted_attributes_for(controller::PERMIT_CREATE),
      update: controller.try(:permitted_attributes_for_update) || permitted_attributes_for(controller::PERMIT_UPDATE),
    }[action.to_sym]
  end

  def permitted_attributes_for(permits)
    raise "NO PERMITTED ATTRIBUTES DEFINED" unless permits.is_a?(Array)
    permits.collect do |_name|
      _name.is_a?(Hash) ? _name.keys : _name
    end.flatten
  end

  def candos(action)
    controller.new.send(:cando)[action] rescue nil
  end

  def additional_paragraphs(action)
    [((controller_swagger.dig(:description, action) || []) rescue [])].flatten.compact
  end

  def model_name(**args)
    model.model_name.human(**args)
  end

  def action_suffix
    controller_swagger.dig(:action_suffix) rescue nil
  end

  def title(action)
    controller_swagger.dig(action) || {
      index:   "List #{model_name(count: 2)} #{action_suffix}".strip,
      show:    "Show #{model_name} #{action_suffix}".strip,
      create:  "Create #{model_name} #{action_suffix}".strip,
      update:  "Update #{model_name} #{action_suffix}".strip,
      destroy: "Delete #{model_name} #{action_suffix}".strip
    }[action]
  end

  def description(action)
    _candos = candos(action)
    _description = []
    if _candos.is_a?(Array)
      _description << "To use this endpoint the current user needs to be authorized for the tenant to do any of these\n        - #{_candos.join("\n        - ")}"
    end
    if additional_paragraphs(action).any?
      _description += additional_paragraphs(action)
    end

    # _description += ["Controller: `#{controller}` - Route name: `#{file_name}`"]
    _description << "Controller: `#{controller}`\n"

    if _description.any?
      <<~EOF
        description <<~EOM
                #{_description.join("\n        ---\n        ")}
              EOM
      EOF
    end
  end

  def path_parameters(singularize: true)
    _route_name = singularize ? file_name.singularize : file_name
    _names = required_parts(_route_name)
    return unless _names.is_a?(Hash)
    _names.keys.collect do |name|
      <<~EOF
        parameter name: "#{name}", in: :path,
                  type: :string,
                  required: true,
                  description: "#{model_name} #{name}"
      EOF
    end.join("\n")
  end

  def resource_plural
    model.name.pluralize
  end

  def resource_singular
    model.name
  end

  def serializer
    @serializer ||= controller::SERIALIZER || nil
  end

  def serializer_overview
    @serializer_overview ||= controller::OVERVIEW_SERIALIZER || nil
  end

  def gridfilter_fields(action)
    model_action(action).gridfilter_fields
  end

end
