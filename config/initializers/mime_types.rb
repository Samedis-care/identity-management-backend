# Be sure to restart your server when you modify this file.

# Add new mime types for use in respond_to blocks:
# Mime::Type.register "text/richtext", :rtf
#Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx
Mime::Type.register "application/json", :xlsx

# Register JSON again so it's the default in the chain
Mime::Type.register "application/vnd.api+json", :json
Mime::Type.register "application/json", :json
