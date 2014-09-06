require 'securerandom'
require_relative 'http_utils'

class MailgunApi

  attr_accessor :key, :base_url, :content_type

  def initialize(opts={})
    @opts = opts
    @key = opts[:api_key]
    @base_url = opts[:api_base_url]
    @content_type = "multipart/form-data; boundary=#{multipart_form_data_boundary}"
    @attachment_location = opts[:attachment_dir] || Rails.root.join('public', 'uploads').to_s
    @sender = opts[:default_sender] || "donotreply@donotreply.com"
    @user = opts[:api_user]
    @logger = Rails.logger
  end

  def send_message_url
    uri = URI(File.join(@base_url, 'messages'))
    uri.user = @user
    uri.password = @key
    uri.to_s
  end

  def message_events_url
    uri = URI(File.join(@base_url, 'events'))
    uri.user = @user
    uri.password = @key
    uri.to_s

  end

  def multipart_form_data_boundary
    @form_boundary ||= SecureRandom::hex.to_s + "MultipartFormDataBoundary"
    return @form_boundary
  end

  def multipart_mixed_boundary
    @mixed_boundary ||= SecureRandom::hex.to_s + "MultipartMixedBoundary"
    return @mixed_boundary
  end

  def form_data_name_value_string(hash)
    string = ""
    hash.each do |key, value|
      string += "--#{multipart_form_data_boundary}\r\n" +
          "Content-Disposition: form-data; name=\"#{key}\"\r\n" +
          "\r\n" +
          "#{value}\r\n"
    end
    return string
  end

  def form_data_file_string(file)
    file.rewind
    headers = file.headers.split(';')
    headers[1] = " name=\"attachment[]\""
    headers = headers.join(';')

    string = "--" + multipart_form_data_boundary + "\r\n" + headers +
        "\r\n"
    @logger.debug string
    string += "#{file.read}"
    return string
  end

  def create_send_email_params(email_params)
    mailgun_params = {}
    mailgun_params[:to] = email_params[:to]
    mailgun_params[:subject] = email_params[:subject]
    mailgun_params[:from] = @sender
    mailgun_params[:text] = email_params[:body] || ""
    return mailgun_params
  end

  def create_send_message_body(email_params)
    #TODO do not create the attachments body multiple times
    attachments = email_params[:attachment]
    attachments_body = if attachments
                         attachments.map { |file| form_data_file_string(file) }.join('')
                       else
                         ""
                       end
    body = form_data_name_value_string(create_send_email_params(email_params))

    @logger.debug("#{self.to_s}: Email body: #{body}")
    body += attachments_body + "\r\n--#{multipart_form_data_boundary}--\r\n"
    body
  end

  def send_message(email_params)
    body = create_send_message_body(email_params)
    begin
      response = HttpUtils.http_post(send_message_url, body, :content_type => @content_type)
    rescue SystemCallError => error
      @logger.error("Encountered operating system error: #{error.inspect}")
      @logger.error error.backtrace.join("\r\n")
      return [Email::Status::FAILED, nil, self.to_s]
    end
    message_id = nil
    response_body = JSON.parse(response.body)
    @logger.debug("#{self.to_s}: Response code = #{response.code}")
    @logger.debug("#{self.to_s}: Response body = #{response.body}")
    if not response.code =~ /200/

      state = Email::Status::FAILED
    else
      match = /^<(?<message_id>.*)>$/.match response_body['id']
      message_id = match[:message_id]
      state = Email::Status::SENDING
    end
    return [state, message_id, self.to_s]
  end

  def get_message_status(id)
    params = {}
    params["message-id"] = id
    params["event"] = 'rejected OR failed'

    @logger.debug("#{self.to_s}: Query if rejected or failed email")
    response = HttpUtils.http_get(message_events_url, params)

    if not response.code =~ /200/
      @logger.debug("Response code: #{response.code}")
      @logger.debug("Response body: #{response.body}")
      return [Email::Status::FAILED, id, self.to_s]
    end
    if JSON.parse(response.body)['items'].any?
      return [Email::Status::FAILED, id, self.to_s]
    end

    params["event"] = "delivered"
    @logger.debug("#{self.to_s}: Query if delivered email")
    response = HttpUtils.http_get(message_events_url, params)
    if not response.code =~ /200/
      @logger.debug("Response code: #{response.code}")
      @logger.debug("Response body: #{response.body}")
      return [Email::Status::FAILED, id, self.to_s]
    end
    if JSON.parse(response.body)["items"].any?
      return [Email::Status::SENT, id, self.to_s]
    end
    return [Email::Status::SENDING, id, self.to_s]
  end

  def to_s
    'mailgun'
  end


end