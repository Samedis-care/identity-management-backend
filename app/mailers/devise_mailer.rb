class DeviseMailer < Devise::Mailer
  layout 'mailer'

  def unlock_instructions(user, token, opts = {})
    headers ApplicationMailer.default_headers

    @token = token

    @app_context = user.app_context
    @app = app
    prepare_logo

    opts[:from] = @app.config.mailer.from
    opts[:reply_to] = @app.config.mailer.reply_to
    use_styles

    @url = v1_user_unlock_url(unlock_token: token, app: @app_context)

    devise_mail(user, :unlock_instructions, opts)
  end

  def confirmation_instructions(user, token, opts = {})
    headers ApplicationMailer.default_headers

    @app_context = user.app_context
    @app = app
    prepare_logo

    opts[:from] = @app.config.mailer.from
    opts[:reply_to] = @app.config.mailer.reply_to
    use_styles

    @url = user.redirect_url_confirm_account({ HOST: User.host('identity-management'), APP: @app_context, TOKEN: token, INVITE_TOKEN: user.invite_token })
    if user.confirmed_at
      # account was previously confirmed and is not new
      # so we only mention email change and not account creation
      opts[:subject] = I18n.t('devise.mailer.email_change.subject')
      @url << '&reason=email_change'

      devise_mail(user, :confirmation_email_change, opts)
    else
      devise_mail(user, :confirmation_instructions, opts)
    end
  end

  def recovery_confirmation_instructions(user, token, opts = {})
    headers ApplicationMailer.default_headers

    @app_context = user.app_context
    @app = app
    prepare_logo
    @url = user.redirect_url_confirm_recovery_email({ HOST: User.host('identity-management'), APP: @app_context, TOKEN: token })
    opts[:from] = @app.config.mailer.from
    opts[:reply_to] = @app.config.mailer.reply_to
    use_styles

    devise_mail(user, :recovery_confirmation_instructions, opts)
  end

  def recovery_instructions(user, token, opts = {})
    headers ApplicationMailer.default_headers

    @app_context = user.app_context
    @app = app
    prepare_logo
    @url = user.redirect_url_recover_account({ HOST: User.host('identity-management'), APP: @app_context, TOKEN: token })
    opts[:from] = @app.config.mailer.from
    opts[:reply_to] = @app.config.mailer.reply_to
    use_styles

    devise_mail(user, :recovery_instructions, opts)
  end

  def reset_password_instructions(user, token, opts = {})
    headers ApplicationMailer.default_headers

    @app_context = user.app_context
    @app = app
    prepare_logo
    @url = user.redirect_url_reset_password({ HOST: User.host('identity-management'), APP: @app_context, TOKEN: token })
    @user_name = user.name
    opts[:from] = @app.config.mailer.from
    opts[:reply_to] = @app.config.mailer.reply_to
    use_styles
    super
  end

  def password_change(user, opts = {})
    headers ApplicationMailer.default_headers

    @app_context = user.app_context
    @app = app
    prepare_logo
    @user = user
    opts[:subject] = I18n.t('devise.mailer.password_change.subject')
    opts[:from] = @app.config.mailer.from
    opts[:reply_to] = @app.config.mailer.reply_to
    use_styles
    super
  end

  def email_changed(user, opts = {})
    headers ApplicationMailer.default_headers

    @app_context = user.app_context
    @app = app
    prepare_logo
    @user = user
    @user_name = user.name
    opts[:subject] = I18n.t('devise.mailer.email_change.subject')
    opts[:from] = @app.config.mailer.from
    opts[:reply_to] = @app.config.mailer.reply_to
    use_styles
    super
  end

  def use_styles
    @app = app
    @color = OpenStruct.new(
      background: "#{@app.config.theme.background.default || '#e1e2e1' }",
      content: "#{@app.config.theme.mode.eql?('light') ? '#FFF' : '#121212'}",
      primary: OpenStruct.new(
        main:  "#{@app.config.theme.primary.main || '#0277bc'}",
        light: "#{@app.config.theme.primary.light || '#5e91f2'}",
        dark:  "#{@app.config.theme.primary.dark || '#003b8e'}"
      ),
      secondary: OpenStruct.new(
        main:  "#{@app.config.theme.secondary.main || '#00bcd4'}",
        light: "#{@app.config.theme.secondary.light || '#62efff'}",
        dark:  "#{@app.config.theme.secondary.dark || '#008ba3'}"
      )
    )
    @style = OpenStruct.new(
      font_family: 'font-family: sans-serif',
      font_size: 'font-size: 16px',
      line_height: '',
      color: "#{@app.config.theme.mode.eql?('light') ? '#000' : '#FFF'}",
      background: "background-color: #{@color.background};",
      content: "background-color: #{@color.content};",
      primary: OpenStruct.new(
        main:  "background-color: #{@color.primary.main};",
        light: "background-color: #{@color.primary.light};",
        dark:  "background-color: #{@color.primary.dark};",
      ),
      secondary: OpenStruct.new(
        main:  "background-color: #{@color.secondary.main};",
        light: "background-color: #{@color.secondary.light};",
        dark:  "background-color: #{@color.secondary.dark};",
      )
    )
    @tag_style = OpenStruct.new(
      ul: "margin:0; margin-left: 25px; padding:0; #{@style.font_family}; #{@style.font_size}; #{@style.line_height}",
      td: "#{@style.font_family}; #{@style.font_size}; #{@style.line_height}; word-break: break-word",
      h2: "#{@style.font_family}; #{@style.font_size}; #{@style.line_height}; margin-top: 15px",
      h3: "#{@style.font_family}; #{@style.font_size}; #{@style.line_height}; margin-top: 10px",
      p: "#{@style.font_family}; #{@style.font_size}; #{@style.line_height}",
      a: "#{@style.font_family}; #{@style.font_size}; #{@style.line_height}",
      small: "#{@style.font_family}; font-size: 80%; #{@style.line_height}",
    )
  end

  def mail(headers = {}, &block)
    return super unless (app.config.try(:mailer).try(:smtp_settings) rescue nil)

    headers[:delivery_method_options] = ActionMailer::Base.smtp_settings.merge(app.config.mailer.smtp_settings.delivery_method_options)
    super
  end

  def app_context=(ac)
    @app_context = ac
  end

  def app_context
    @app_context ||= 'identity-management'
  end

  private

  def locale_vars
    if (@user.is_a?(User) rescue false)
      { user_name: @user.name, email: @user.email, app_name: app&.full_name }
    else
      {}
    end
  end

  # override default devise subject to inject locale vars
  def subject_for(key)
    I18n.t(:"#{devise_mapping.name}_subject", scope: [:devise, :mailer, key],
      default: [:subject, key.to_s.humanize], **locale_vars)
  end

  def app
    @app ||= Actors::App.named(app_context).first
  end

  def logo
    @logo ||= begin
      _logo_b64 = app.config.try(:mailer).try(:logo_b64) rescue nil
      return nil unless _logo_b64.present?

      _file = Base64StringIO.from_base64(_logo_b64, 'logo')
      _file.try :rewind
      _file.binmode
      _tmp = Tempfile.new(_file.original_filename)
      _tmp.binmode
      _tmp.write _file.read
      _tmp.try :rewind
      _logo = Vips::Image.new_from_file _tmp.path
      attachments.inline['logo.png'] = _tmp.read
      _tmp.close
      _tmp.delete
      _logo
    end
  end

  def logo_size
    @logo_size ||= begin
      width = 250
      _logo = logo
      return "" if _logo.nil?
      "#{width}x#{(_logo.height / (_logo.width.to_f / width)).to_i}"
    end
  end

  def logo_width
    @logo_width ||= begin
      logo_size.split('x')[0]
    end
  end

  def logo_height
    @logo_height ||= begin
      logo_size.split('x')[1]
    end
  end

  def logo_style
    @logo_style ||= begin
      _width, _height = logo_size.split('x')
      "width:#{_width}px; height:#{_height}px;"
    end
  end

  def prepare_logo
    logo
    logo_size
    logo_width
    logo_height
    logo_style
    @logo
  end

end
