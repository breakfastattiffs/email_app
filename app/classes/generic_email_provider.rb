require_relative 'mandrill_api'
require_relative 'mailgun_api'
require 'timeout'

class GenericEmailProvider
  DEFAULT_CONFIG_FILE = "#{Rails.root.to_s}/config/email_provider.yml"

  attr_accessor :name, :config_file

  def initialize(config_file_path=nil)
    config_file_path = config_file_path || DEFAULT_CONFIG_FILE
    @config_file = HashWithIndifferentAccess.new(YAML.load(File.open(config_file_path)))
    @mandrill_api = MandrillApi.new(@config_file[:mandrill])
    @logger = Rails.logger
  end

  def send_message(opts={}, email)
    @mandrill_api = MandrillApi.new(@config_file[:mandrill])
    #
    # [Email::Status::TRY_AGAIN, 'testid', 'testservice']
    state, id, service = @mandrill_api.send_message(opts)
    update_email(email, state, id, service)

    # Check on the status of the message
    if state == Email::Status::SENDING
      p1 = Process.fork do
        begin
          Timeout::timeout(300) {
            while state == Email::Status::SENDING or state == Email::Status::UNKNOWN
              sleep 30
              state, id, service = @mandrill_api.get_message_status(id)
            end
          }
        rescue Timeout::Error => e
          @logger.error "Timed out checking status of mandrill email"
          state = Email::Status::TRY_AGAIN
        end

        update_email(email, state, id, service)

        if state == Email::Status::TRY_AGAIN
          backup_send_message(opts, email)
        end
      end
      @logger.debug "Forked pid #{p1} to check on status of mandrill email"

      Process.detach p1
    elsif state == Email::Status::TRY_AGAIN
      # Send using mailgun since sending with mandrill failed
      backup_send_message(opts, email)
    end
  end

  def backup_send_message(email_params, email)
    @mailgun_api ||= MailgunApi.new(@config_file[:mailgun])

    @logger.debug "Sending backup email..."
    p1 = Process.fork do
      state, id, service = @mailgun_api.send_message(email_params)
      update_email(email, state, id, service)

      p2 = Process.fork do
        begin
          Timeout::timeout(600) {
            while state == Email::Status::SENDING
              sleep 60
              state, id, service = @mailgun_api.get_message_status(id)
            end
          }
        rescue Timeout::Error => e
          @logger.error("Timed out checking status for email sent using mailgun")
          exit
        end

        update_email(email, state, id, service)
      end
      @logger.debug "Forked to check on status of mailgun email: #{p2}"

      Process.detach p2
    end
    @logger.debug "Send email using mailgun. Fork a process pid #{p1}."

    Process.detach p1
  end

  def update_email(email, status=nil,message_id=nil,provider=nil)
    @logger.debug("Updating email with status: %s, id: %s, service provider: %s" %
    [status, message_id, provider])
    email.status = status
    email.message_id = message_id
    email.sending_service = provider
    email.save
  end
end