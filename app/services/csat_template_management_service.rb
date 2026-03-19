class CsatTemplateManagementService
  DEFAULT_BUTTON_TEXT = 'Please rate us'.freeze
  DEFAULT_LANGUAGE = 'en'.freeze

  def initialize(inbox)
    @inbox = inbox
  end

  def template_status
    template = @inbox.csat_config&.dig('template')
    return { template_exists: false } unless template

    if @inbox.twilio_whatsapp?
      get_twilio_template_status(template)
    elsif evolution_provider?
      # Non-official providers (Baileys/Evolution API) don't use Meta-approved
      # CSAT templates, so we report as not existing.
      { template_exists: false }
    else
      get_whatsapp_template_status(template)
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching CSAT template status: #{e.message}"
    { service_error: e.message }
  end

  def create_template(template_params)
    validate_template_params!(template_params)

    delete_existing_template_if_needed

    result = create_template_via_provider(template_params)
    update_inbox_csat_config(result) if result[:success]

    result
  rescue StandardError => e
    Rails.logger.error "Error creating CSAT template: #{e.message}"
    { success: false, service_error: 'Template creation failed' }
  end

  private

  def validate_template_params!(template_params)
    raise ActionController::ParameterMissing, 'message' if template_params[:message].blank?
  end

  def create_template_via_provider(template_params)
    if @inbox.twilio_whatsapp?
      create_twilio_template(template_params)
    elsif evolution_provider?
      # We don't support Meta template creation for non-official providers.
      # Return success so the UI can save CSAT settings without requiring
      # a Meta OAuth token.
      template_config = build_template_config(template_params)
      {
        success: true,
        template_name: template_config[:template_name],
        template_id: nil,
        language: template_config[:language],
        status: 'PENDING'
      }
    else
      create_whatsapp_template(template_params)
    end
  end

  def create_twilio_template(template_params)
    template_config = build_template_config(template_params)
    template_service = Twilio::CsatTemplateService.new(@inbox.channel)
    template_service.create_template(template_config)
  end

  def create_whatsapp_template(template_params)
    template_config = build_template_config(template_params)
    Whatsapp::CsatTemplateService.new(@inbox.channel).create_template(template_config)
  end

  def build_template_config(template_params)
    {
      message: template_params[:message],
      button_text: template_params[:button_text] || DEFAULT_BUTTON_TEXT,
      base_url: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
      language: template_params[:language] || DEFAULT_LANGUAGE,
      template_name: CsatTemplateNameService.csat_template_name(@inbox.id)
    }
  end

  def update_inbox_csat_config(result)
    current_config = @inbox.csat_config || {}
    template_data = build_template_data_from_result(result)
    updated_config = current_config.merge('template' => template_data)
    @inbox.update!(csat_config: updated_config)
  end

  def build_template_data_from_result(result)
    if @inbox.twilio_whatsapp?
      build_twilio_template_data(result)
    else
      build_whatsapp_cloud_template_data(result)
    end
  end

  def build_twilio_template_data(result)
    {
      'friendly_name' => result[:friendly_name],
      'content_sid' => result[:content_sid],
      'approval_sid' => result[:approval_sid],
      'language' => result[:language],
      'status' => result[:whatsapp_status] || result[:status],
      'created_at' => Time.current.iso8601
    }.compact
  end

  def build_whatsapp_cloud_template_data(result)
    {
      'name' => result[:template_name],
      'template_id' => result[:template_id],
      'language' => result[:language],
      'created_at' => Time.current.iso8601
    }
  end

  def get_twilio_template_status(template)
    content_sid = template['content_sid']
    return { template_exists: false } unless content_sid

    template_service = Twilio::CsatTemplateService.new(@inbox.channel)
    status_result = template_service.get_template_status(content_sid)
    return { template_exists: false, error: 'Template not found' } unless status_result.is_a?(Hash)

    if status_result[:success]
      {
        template_exists: true,
        friendly_name: template['friendly_name'],
        content_sid: template['content_sid'],
        status: status_result[:template][:status],
        language: template['language']
      }
    else
      {
        template_exists: false,
        error: 'Template not found'
      }
    end
  end

  def get_whatsapp_template_status(template)
    return { template_exists: false } if evolution_provider?

    template_name = template['name'] || CsatTemplateNameService.csat_template_name(@inbox.id)
    status_result = Whatsapp::CsatTemplateService.new(@inbox.channel).get_template_status(template_name)
    return { template_exists: false, error: 'Template not found' } unless status_result.is_a?(Hash)

    if status_result[:success]
      {
        template_exists: true,
        template_name: template_name,
        status: status_result[:template][:status],
        template_id: status_result[:template][:id]
      }
    else
      {
        template_exists: false,
        error: 'Template not found'
      }
    end
  end

  def delete_existing_template_if_needed
    template = @inbox.csat_config&.dig('template')
    return true if template.blank?

    if @inbox.twilio_whatsapp?
      delete_existing_twilio_template(template)
    elsif evolution_provider?
      # Nothing to delete on non-official providers.
      true
    else
      delete_existing_whatsapp_template(template)
    end
  rescue StandardError => e
    Rails.logger.error "Error during template deletion for inbox #{@inbox.id}: #{e.message}"
    false
  end

  def delete_existing_twilio_template(template)
    content_sid = template['content_sid']
    return true if content_sid.blank?

    template_service = Twilio::CsatTemplateService.new(@inbox.channel)
    deletion_result = template_service.delete_template(nil, content_sid)

    if deletion_result[:success]
      Rails.logger.info "Deleted existing Twilio CSAT template '#{content_sid}' for inbox #{@inbox.id}"
      true
    else
      Rails.logger.warn "Failed to delete existing Twilio CSAT template '#{content_sid}' for inbox #{@inbox.id}: #{deletion_result[:response_body]}"
      false
    end
  end

  def delete_existing_whatsapp_template(template)
    return true if evolution_provider?

    template_name = template['name']
    return true if template_name.blank?

    csat_template_service = Whatsapp::CsatTemplateService.new(@inbox.channel)
    template_status = csat_template_service.get_template_status(template_name)
    return true unless template_status[:success]

    deletion_result = csat_template_service.delete_template(template_name)
    if deletion_result[:success]
      Rails.logger.info "Deleted existing CSAT template '#{template_name}' for inbox #{@inbox.id}"
      true
    else
      Rails.logger.warn "Failed to delete existing CSAT template '#{template_name}' for inbox #{@inbox.id}: #{deletion_result[:response_body]}"
      false
    end
  end

  def evolution_provider?
    @inbox.channel.try(:provider) == 'evolution_api'
  end
end
