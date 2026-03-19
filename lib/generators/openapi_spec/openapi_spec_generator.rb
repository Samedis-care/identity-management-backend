class OpenapiSpecGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  require_relative 'lib/path_generator'
  require_relative 'lib/meta_generator'
  require_relative 'lib/module_finder'
  require_relative 'lib/helpers'

  include PathGenerator
  include MetaGenerator
  include ModuleFinder
  include OpenapiSpec::Helpers

  include Rails.application.routes.url_helpers

  delegate :url_helpers, to: 'Rails.application.routes'

  def create_openapi_file
    if controller.const_defined?(:JSON_API) && controller::API.present?
      template 'openapi_yaml', File.join('spec/openapi', "#{destination_file}.yaml")
    else
      puts "Skipping: #{controller} as it is not a supported JsonApiController".white
    end
  end

  def self.combine_specs!
    OpenapiSpec::Helpers.available_specs.each do |s|
      paths = {}
      Dir.glob("#{s[:dir]}/paths/**/*.yaml").collect do |endpoint_spec|
        paths.merge! YAML.load_file(endpoint_spec)['paths']
      end

      # sort paths
      paths = paths.sort_by do |_path, details|
        _http_verb, verb_details = details.find { |key, _| %w[get post put delete patch head options].include?(key.to_s) }
        [
          verb_details.fetch('tags', []).join,
          verb_details.fetch('summary', '').split('s:')
        ]
      end.to_h

      puts '-' * 80
      puts " Combining spec: #{s[:file].blue} with their endpoints -> #{s[:destination].blue}"
      s[:spec].merge(
        components: {
          securitySchemes: security_schemes,
          schemas: ModuleFinder.schemas(s[:name]).merge(JsonApi::Schema.new.openapi_default_schemas)
        },
        servers:,
        openapi: '3.1.1',
        paths:
      ).as_json.to_yaml.to_file(s[:destination])
    end
  end

  def self.servers
    [
      {
        url: '{protocol}://{defaultHost}',
        variables: {
          protocol: {
            default: :https
          },
          defaultHost: {
            default: ENV.fetch('HOST', 'localhost:3000')
          }
        }
      }
    ]
  end

  def self.security_schemes
    {
      Bearer: {
        description: <<~DESC,
          # Token based authentication Header
          Authenticate and then copy the token into this field without the "Bearer " prefix.

          ## To obtain a bearer token
          Use the OAuth2 token endpoint.
        DESC
        type: :http,
        scheme: :bearer
      }
    }
  end

  private

  def controller_swagger
    if controller.const_defined?(:SWAGGER) && controller::SWAGGER.is_a?(Hash)
      controller::SWAGGER
    elsif controller.const_defined?(:SWAGGER) && controller::SWAGGER.is_a?(Proc)
      controller::SWAGGER.call
    else
      {}
    end
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
    "#{file_name.gsub(/_index$/,'').singularize}_url"
  end

  # path helper to be used
  def named_path_index
    "#{file_name}_path"
  end

  # path helper to be used
  def named_path
    "#{file_name.gsub(/_index$/,'').singularize}_path"
  end

  def parser
    @parse ||= URI::Parser.new
  end

  def required_parts(route_name)
    required_parts_auto(route_name)
  end

  def required_parts_auto(route_name)
    _parts = [route_name, route_name.singularize, route_name.gsub(/_index$/,'').singularize, route_name.pluralize].compact.collect do |rn|
      route_reqs.dig(rn)&.map { |_part| [_part.to_sym, "{#{_part}}"] }&.to_h || {}
    end.first || {}
  end

  def api_path_index
    _req_parts = required_parts(file_name)
    _path = url_helpers.try(named_path_index, _req_parts)
    parser.unescape _path
  end

  def api_path
    if url_helpers.respond_to? named_path
      _req_parts = required_parts(file_name.gsub(/_index$/,'').singularize)
      _path = url_helpers.try(named_path, _req_parts)
      parser.unescape _path
    elsif url_helpers.respond_to? named_path_index
      api_path_index
    end
  end

  def route_reqs
    @route_reqs ||= Rails.application.routes.set.reject { |r| r.name.blank? }.map do |r|
      [r.name, r.required_parts]
    end.sort.to_h.with_indifferent_access
  end

  def route_set
    @route_set ||= begin
      _rs = {}

      _routes = Rails.application.routes.set

      _routes.each do |r|
        next if r.name.blank?
        next if r.defaults[:controller].blank?
        next if r.defaults[:action].blank?

        _rs[r.name] ||= {}
        _rs[r.name][:controller] = r.defaults[:controller]
        _rs[r.name][:actions] ||= []
        _rs[r.name][:actions] |= [r.defaults[:action]]
      end
      _rs.with_indifferent_access
    end
  end

  def controller_actions
    @controller_actions ||= begin
      _rs = {}
      _routes = Rails.application.routes.set.collect &:defaults
      _routes.each do |r|
        next if r.blank?
        next if r[:controller].blank?
        next if r[:action].blank?

        _rs[r[:controller]] ||= []
        _rs[r[:controller]] |= [r[:action]]
      end
      _rs.with_indifferent_access
    end
    @controller_actions
  end

  def actions
    _route = route_set.dig(file_name)
    controller_actions[_route[:controller]].sort
  end

  def destination_file
    @destination_file ||= begin
      _route = route_set.dig(file_name)
      _path = "#{controller::API}/paths/#{_route.dig(:controller)}"
      raise "failed to detect path for: #{file_name}" if _path.blank?
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
    return controller.name.split('::')[1].downcase
  end

  def spec_file
    "#{api_version}/#{controller::API}.yaml"
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
    }[action.to_sym]&.sort
  end

  def permitted_attributes_for(permits)
    raise "NO PERMITTED ATTRIBUTES DEFINED" unless permits.is_a?(Array)
    permits.collect do |_name|
      _name.is_a?(Hash) ? _name.keys : _name
    end.flatten
  end

  def controller_candos
    controller.new.send(:cando) rescue {}
  end

  def candos(action)
    _candos = controller_candos
    _ret = _candos.fetch(action.to_sym, _candos.fetch(:all, []))
    unless _ret.any?
      puts '-' * 80
      puts "#{controller} / #{action}"
      puts '-' * 80
      puts '-' * 80
      raise "No candos for action >#{action}< defined. Either add candos for the action or undefine the controller method and route (route actions: #{actions * ', '})."
    end
    _ret
  end

  def additional_paragraphs(action)
    [((controller_swagger.dig(:description, action) || []) rescue [])].flatten.compact
  end

  def model_name(**args)
    controller_swagger.dig(:name) || model.model_name.human(**args) rescue model.to_s
  end

  def action_suffix
    controller_swagger.dig(:action_suffix) rescue nil
  end

  # in api-docs this will be the collapsible menu group
  def tag
    controller_swagger.fetch(:tag, model_name(count: 2))
  end

  # in api-docs this will be the collapsible menu group
  def tags(_action)
    [tag].compact.uniq.sort
  end

  def operation_id(action)
    _base = controller.to_s.gsub(/^Api::V\d+::/, '').gsub(/::/, '-').gsub(/Controller$/, '').downcase
    "#{_base}-#{action}"
  end

  # in api-docs this will be the menu link
  def title(action)
    controller_swagger.dig(action) || {
      index:   "#{model_name(count: 2)}: List [GET] #{action_suffix}".strip,
      show:    "#{model_name}: Show [GET] #{action_suffix}".strip,
      create:  "#{model_name}: Create [POST] #{action_suffix}".strip,
      update:  "#{model_name}: Update [PUT] #{action_suffix}".strip,
      destroy: "#{model_name}: Delete [DELETE] #{action_suffix}".strip
    }.with_indifferent_access[action]
  end

  def controller_header
    controller_swagger.dig(:header)
  end

  def description(action)
    _candos = candos(action)
    _description = [controller_header].compact
    if _candos.is_a?(Array)
      _description << <<~EOF
        To use this endpoint the current user needs to be authorized for the
        tenant to do any of these\n
         - #{_candos.join("\n - ")}
        \n
      EOF
    end
    if additional_paragraphs(action).any?
      _description += additional_paragraphs(action)
    end

    return unless _description.any?

    _description.collect(&:strip).join("\n\n---\n\n")
  end

  def needs_tenant_context?(action)
    return false if candos(action).include?('public')
    return false if path_parameters_keys(action).keys.include?(:tenant_id)

    true
  end

  def query_parameters(action)
    return unless needs_tenant_context?(action)

    {
      name: :tenant_id,
      in: :query,
      required: true,
      schema: { type: :string },
      description: <<~DESC
        The tenant context is required to determine if the user has
        the required privileges.
      DESC
    }
  end

  def path_parameters_keys(action)
    singularize = !%w(index create).include?(action.to_s)
    _route_name = singularize ? file_name.gsub(/_index$/, '').singularize : file_name
    required_parts(_route_name)
  end

  def path_parameter_options(name)
    _ppo = controller_swagger.dig(:path_parameter, name.to_sym) ||
      { description: "#{model_name} #{name}" }
    _ppo = { name:, in: :path, required: true }.merge(_ppo)
    _ppo[:schema] ||= { type: :string }
    _ppo.deep_stringify_keys
  end

  def path_parameters(action)
    _names = path_parameters_keys(action)
    return unless _names.is_a?(Hash)

    _names.keys.collect do |name|
      path_parameter_options(name)
    end
  end

  def route_name
    file_name
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

  def overview_serializer
    @overview_serializer ||= controller::OVERVIEW_SERIALIZER || nil
  end

  def gridfilter_fields(action)
    return nil unless model.respond_to?(:gridfilter_fields)

    @gridfilter_fields ||= model_action(action).gridfilter_fields.collect(&:to_s).sort
    return nil unless @gridfilter_fields.is_a?(Array) && @gridfilter_fields.any?

    @gridfilter_fields
  end

end
