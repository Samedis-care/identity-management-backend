# Preview all emails at http://localhost:3000/rails/mailers/user_mailer
class DeviseMailerPreview < ActionMailer::Preview

  # Preview this email at http://localhost:3000/rails/mailers/devise_mailer/password_change
  def password_change
    user = User.find(User.available.limit(100).pluck(:_id).sample)
    user.app_context = app.name
    DeviseMailer.password_change(user)
  end

  # Preview this email at http://localhost:3000/rails/mailers/devise_mailer/email_changed
  def email_changed
    user = User.find(User.available.limit(100).pluck(:_id).sample)
    user.unconfirmed_email ||= "abc.123.#{user.email}"
    user.app_context = app.name
    DeviseMailer.email_changed(user)
  end

  # Preview this email at http://localhost:3000/rails/mailers/devise_mailer/confirmation_instructions
  def confirmation_instructions
    user = User.find(User.available.limit(100).pluck(:_id).sample)
    user.unconfirmed_email ||= "abc.123.#{user.email}"
    user.app_context = app.name
    DeviseMailer.confirmation_instructions(user, token="X"*32)
  end

  # Preview this email at http://localhost:3000/rails/mailers/devise_mailer/reset_password_instructions
  def reset_password_instructions
    user = User.find(User.available.limit(100).pluck(:_id).sample)
    user.app_context = app.name
    DeviseMailer.reset_password_instructions(user, token="X"*32)
  end

  private

  def app
    @app ||= Actors::App.last
  end

end
