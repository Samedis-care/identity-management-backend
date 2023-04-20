# use these via
#           include_examples :paging
RSpec.shared_examples :paging do
  parameter name: 'page', in: :query,
            type: :string,
            'x-example': '1',
            description: 'the page number'
  parameter name: 'per_page', in: :query,
            type: :string,
            'x-example': '10',
            description: 'the number of records per page (might be limited on the server side)'
  parameter name: 'padding', in: :query,
            type: :string,
            'x-example': '0',
            description: 'manually adjust db offset: (page*per_page)+padding'
end

RSpec.shared_examples :quickfilter do
  parameter name: 'quickfilter', in: :query,
            type: :string,
            description: 'performs a search in keywords'
end

# include_examples :tenant_id
# include_examples :tenant_id, :query
RSpec.shared_examples :tenant_id do |_in|
  parameter name: 'tenant_id', in: _in||:path,
            type: :string,
            required: true,
            description: 'tenant id context'
end

# include_examples :path_ids, [:ressource_id, :id]
RSpec.shared_examples :path_ids do |_names|
  _names.each do |name|
    parameter name: name, in: :path,
              type: :string,
              required: true,
              description: "record #{name}"
  end
end

# include_examples :upload_file
RSpec.shared_examples :upload_file do |_names|
  parameter name: 'data[document]', in: :formData,
            type: :file,
            'x-example': 'data:application/pdf;base64,...',
            description: <<~EOF
              The file to upload. Within Swagger-UI this is using form uploads
              as handling large Base64 strings in this scenario is highly impractical.
              **Instead of multipart/form-data this can also be sent as a Base64 encoded string**
            EOF
  parameter name: 'data[name]', in: :formData,
            type: :string,
            'x-example': 'sample.pdf',
            description: 'Name of the upload file'
end

# include_examples :upload_image
RSpec.shared_examples :upload_image do |_names|
  parameter name: 'data[image]', in: :formData,
            type: :file,
            'x-example': 'data:application/pdf;base64,...',
            description: <<~EOF
              The file to upload. Within Swagger-UI this is using form uploads
              as handling large Base64 strings in this scenario is highly impractical.
              **Instead of multipart/form-data this can also be sent as a Base64 encoded string**
            EOF
  parameter name: 'data[name]', in: :formData,
            type: :string,
            'x-example': 'sample.png',
            description: 'Name of the upload file'
  parameter name: 'data[primary]', in: :formData,
            type: :boolean,
            description: 'When `true` this image will become the new primary for the associated ressource'
end

# include_examples :sorting
# include_examples :sorting, :formData
RSpec.shared_examples :sorting do |_in|
  parameter name: 'sort', in: _in||:query,
            type: :string,
            description: <<~EOF
              JSON Array of Objects to sort the results by one
              or more fields in the requested order.
              Example:
              `[{ property: "field1", direction: "ASC" }, { property: "field2", direction: "DESC" }]`
            EOF
end

# include_examples :gridfilter
# include_examples :gridfilter, :query, Model.gridfilter_fields
RSpec.shared_examples :gridfilter do |_in, _gridfilter_fields|
  parameter name: 'gridfilter', in: _in||:query,
            type: :string,
            description: <<~EOF
       String in JSON format as described in https://www.ag-grid.com/javascript-grid-filtering/

       <details>
         <summary>The model defined these fields as allowed for filtering.</summary>
         #{(_gridfilter_fields||[]).collect{|c| "`#{c}`"}.join(', ')}
       </details>

       <details>
         <summary>Detailed example</summary>
         ```json
          {
            "created_at":{
              "filterType":"date",
              "type":"inRange",
              "dateFrom":"2019-03-31",
              "dateTo":"2019-07-31"
            },
            "sign_in_count":{
              "condition1":{
                "filterType":"number",
                "type":"inRange",
                "filter":0,
                "filterTo":1000000
              },
              "condition2":{
                "filterType":"number",
                "type":"notEqual",
                "filter":"666.777"
              },
              "filterType":"number",
              "operator":"AND"
            },
            "email":{
              "condition1":{
                "filterType":"text",
                "type":"contains",
                "filter":"gmail.com"
              },
              "condition2":{
                "filterType":"text",
                "type":"equals",
                "filter":"tdouglas@domain.local"
              },
              "filterType":"text",
              "operator":"OR"
            },
            "first_name":{
              "condition1":{
                "filterType":"text",
                "type":"endsWith",
                "filter":"gan"
              },
              "condition2":{
                "filterType":"text",
                "type":"startsWith",
                "filter":"Te"
              },
              "filterType":"text",
              "operator":"AND"
            },
            "last_name":{
              "filterType":"text",
              "type":"notContains",
              "filter":"Brakus"
            }
          }
         ```
       </details>
  EOF
end