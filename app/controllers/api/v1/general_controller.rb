class Api::V1::GeneralController < ApplicationController
  skip_before_action :check_maintenance_mode

  def server_under_maintenance
    info = MaintenanceMode.current
    render json: {
      success: info.enabled?,
      writable: info.write_allowed?,
      readable: info.read_allowed?,
      code: 200
    }
  end

  def maintenance
    render json: { identity_management: MaintenanceMode.info.to_h }
  end
end
