module OpenapiSpecGenerator::PathGenerator

  # the url part as key with their http actions in the second level
  def paths
    @paths = {}
    @actions = actions
    @actions.intersection(%w(index create)).each do |action|
      @paths[api_path_index] ||= {}
      @paths[api_path_index].merge! spec(action)
    end
    @actions.intersection(%w(show update destroy)).each do |action|
      @paths[api_path] ||= {}
      @paths[api_path].merge! spec(action)
    end

    @paths
  end

  def request_body(action)
    return unless %w(create update).include?(action.to_s)

    only = attributes(action.to_sym)
    {
      required: true,
      content: {
        'application/json': {
          schema: serializer::Schema.new.openapi_consumes_schema(only:)
        },
        'application/x-www-form-urlencoded': {
          schema: serializer::Schema.new.openapi_consumes_form_data_schema(only:)
        },
        'multipart/form-data': {
          schema: serializer::Schema.new.openapi_consumes_form_data_schema(only:)
        }
      }
    }
  end

  def responses(action = nil)
    @responses = {}

    case action.to_sym
    when :index
      response '200', "#{resource_name_index} list" do
        schema **controller.schema(overview: true)
      end
    when :show
      response '200', "#{resource_name_show} view" do
        schema **controller.schema(overview: false)
      end
    when :create
      response '200', "#{resource_name_create} created" do
        schema **controller.schema(overview: false)
      end
    when :update
      response '200', "#{resource_name_update} updated" do
        schema **controller.schema(overview: false)
      end
    when :destroy
      response '200', "#{resource_name_destroy} deleted" do
        schema **serializer::Schema.new.openapi_component_meta_ref
      end

      response '409', 'Conflict' do
        schema type: :object,
               description: <<~DESC.chomp,
                 Some server side rule prevented finishing this request.
                 For example a multi delete might not have worked on all
                 requested records due to some rule not allowing the delete.
                 Please refer to the details in the response like
                 - `meta.msg.error` error identifier
                 - `meta.msg.message` message being displayed
                 - `meta.msg.error_details` showing the attribute causing the problem
               DESC
               properties: {
                 meta: { '$ref': '#/components/schemas/meta' }
               }
      end
    end

    response '400', 'Some values that were sent couldn\'t be processed' do
      schema type: :object,
             description: 'Check the returned info in meta/msg for details',
             properties: {
               meta: { '$ref': '#/components/schemas/meta' }
             }
    end

    response '429', 'Too many requests' do
      schema type: :object,
             description: 'Wait for so many seconds as returned in the Retry-After header before accessing this endpoint again',
             properties: {
               meta: { '$ref': '#/components/schemas/meta' }
             }
    end

    response '401', 'Unauthenticated' do
      schema type: :object,
             description: 'Requires a valid login',
             properties: {
               meta: { '$ref': '#/components/schemas/meta' }
             }
    end

    response '403', 'Unauthorized access' do
      schema type: :object,
             description: 'User is missing the access rights to do this',
             properties: {
               meta: { '$ref': '#/components/schemas/meta' }
             }
    end

    @responses
  end

  def response(http_status, description, **kwargs, &block)
    content_type = kwargs.delete(:content_type) || 'application/json'

    @responses ||= {}
    @responses[http_status] = {
      description:,
      content: {
        content_type => {
          schema: block.call
        }
      }
    }
  end

  def schema(**kwargs)
    kwargs.to_h
  end

  def parameters(action)
    @parameters = []
    @parameters << query_parameters(action)
    @parameters << path_parameters(action)
    locale_parameters(action)
    format_parameters(action)
    quickfilter_paramter(action)
    paging_parameters(action)
    sorting_parameters(action)
    gridfilter_parameters(action)
    @parameters.flatten.compact.uniq
  end

  def parameter(**kwargs)
    @parameters ||= []
    @parameters << kwargs.to_h
  end

  def quickfilter_paramter(action)
    return unless action.to_sym.eql?(:index)
    return unless model.respond_to?(:quickfilter)

    parameter name: 'quickfilter', in: :query,
              schema: { type: :string },
              description: 'performs a search in keywords'
  end

  def gridfilter_parameters(action = nil)
    return unless action.to_sym.eql?(:index)
    return unless model.respond_to?(:gridfilter_fields)

    _gridfilter_fields = gridfilter_fields(:index)
    return unless _gridfilter_fields.try(:any?)

    parameter name: 'gridfilter', in: :query,
              schema: { type: :string },
              description: <<~EOF
                String in JSON format for grid-based filtering.

                <details>
                  <summary>The model defined these fields as allowed for filtering.</summary>

                  #{_gridfilter_fields.collect { |c| "`#{c}`" }.join(', ')}

                </details>
              EOF
  end

  def sorting_parameters(action = nil)
    return unless action.to_sym.eql?(:index)

    parameter name: 'sort', in: :query,
              schema: { type: :string },
              description: <<~EOF
                JSON Array of Objects to sort the results by one
                or more fields in the requested order.
                Example:
                `[{ property: "field1", direction: "ASC" }, { property: "field2", direction: "DESC" }]`
              EOF
  end

  def paging_parameters(action = nil)
    return unless action.to_sym.eql?(:index)

    parameter(name: 'page[number]', in: :query,
              schema: { type: :string },
              'x-example': '1',
              description: <<~DESC)
                the page number (starts at 1, if not given or lower than 1 then
                page 1 will automatically be assumed)'
              DESC
    parameter name: 'page[limit]', in: :query,
              schema: { type: :string },
              'x-example': '10',
              description: 'the number of records per page (might be limited on the server side, use 0 to fetch no data to get only the total count)'
    parameter name: 'padding', in: :query,
              schema: { type: :string },
              'x-example': '0',
              description: 'manually adjust db offset: (page*per_page)+padding not required for normal paging, in doubt omit'

    nil
  end

  def format_parameters(action = nil)
    return nil unless controller_candos[:"#{action}.xlsx"]

    parameter name: 'format', in: :query,
              description: 'this endpoint supports an alternate format for returned data',
              schema: {
                type: :string,
                enum: %i(json xlsx)
              }
  end

  def locale_parameters(_ = nil)
    parameter name: 'locale', in: :query,
              description: 'to control the language returned',
              schema: JsonApi::Schema.new.openapi_component_locales_ref
  end

  # returns the http verb for the action
  def spec_verb(action)
    {
      index: 'get',
      show: 'get',
      create: 'post',
      update: 'put',
      destroy: 'delete'
    }[action.to_sym]
  end

  # all the spec details for an action
  def spec_data(action)
    {
      summary: title(action),
      tags: tags(action),
      operationId: operation_id(action),
      'x-controller': controller.name,
      'x-controller-action': action,
      'x-route-name': route_name,
      'x-candos': candos(action),
      'x-model-type': model.to_s,
      'x-record-type': (serializer || overview_serializer).record_type.to_s,
      'x-gridfilter-fields': gridfilter(action),
      description: description(action),
      security: [{ Bearer: [] }],
      parameters: parameters(action),
      responses: responses(action),
      requestBody: request_body(action)
    }.compact
  end

  def gridfilter(action)
    return unless action.to_sym.eql?(:index)

    gridfilter_fields(action.to_sym)
  end

  # the full verb + spec as content for a path
  def spec(action)
    { spec_verb(action) => spec_data(action) }
  end

end
