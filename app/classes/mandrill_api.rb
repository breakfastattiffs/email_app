require_relative 'http_utils'
require 'json'
require 'pp'

class MandrillApi
  attr_accessor :key, :base_url, :content_type

  def initialize(opts={})
    @opts = opts
    @key = opts[:api_key]
    @base_url = opts[:api_base_url]
    @content_type = "application/json"
    @attachment_location = opts[:attachment_dir] || Rails.root.join('public', 'uploads').to_s
    @sender = opts[:default_sender] || "donotreply@donotreply.com"
    @logger = Rails.logger
  end

  def to_s
    "Mandrill"
  end

  def send_message_url
    File.join(@base_url, "/messages/send.json")
  end

  def info_url
    File.join(@base_url, "/messages/info.json")
  end

  def create_send_message_body(email_params)
    parsed_address_list = Mail::AddressList.new(email_params[:to])
    # List of recipients in json format
    addresses = parsed_address_list.addresses.map do |a|
      address = {}
      address["email"] = a.address
      address["name"] = a.display_name if a.display_name.present?
      address
    end

    # Get from email
    from_email = Mail::Address.new(email_params[:from] || @sender)

    # TODO do not create the attachments body multiple times
    # list of attachments in json format
    attachments = email_params[:attachment]
    attachments = if attachments
                    attachments.map do |a|
                      hash = {}
                      hash["type"] = a.content_type
                      hash["name"] = a.original_filename
                      a.rewind
                      content = a.read
                      encoded_content = Base64.encode64(content)
                      hash["content"] = encoded_content
                      hash
                    end
                  else
                    []
                  end

    json_body = {"key" => @key,
                 "message" =>
                     {
                         "text" => "#{email_params[:body]}",
                         "subject" => "#{email_params[:subject]}",
                         "from_email" => from_email.address,
                         "to" => addresses,
                         "attachments" => nil
                     },
                 "async" => false,
                 "helloworld" => true
    }
    json_body["message"]["from_name"] = from_email.display_name if from_email.display_name.present?
    @logger.debug("Mandrill email body:")
    @logger.debug json_body

    json_body["message"]["attachments"] = attachments

    return json_body.to_json
  end

  def send_message(email_params)
    body = create_send_message_body(email_params)
    response = HttpUtils.http_post(send_message_url, body, :content_type => @content_type)
    @logger.debug("Post to #{send_message_url}")
    @logger.debug("#{self.to_s}. Response code: #{response.code}")

    state = Email::Status::SENDING
    id = nil
    if not response.code =~ /200/
      @logger.debug("#{self.to_s}. Response body: #{response.body}")
      state = Email::Status::TRY_AGAIN
    else
      response_body = JSON.parse(response.body)
      @logger.debug("#{self.to_s}. Response body: #{response_body}")
      if response_body.is_a? Hash
        # hash response means there is an error
        state = Email::Status::TRY_AGAIN
        @logger.debug("#{self.to_s}: error = #{response_body['status']}")
        @logger.debug("#{self.to_s}: message = #{response_body["message"]}")
      else
        # from api docs
        # the sending status of the recipient - either "sent", "queued", "scheduled", "rejected", or "invalid"
        status = response_body.first["status"]
        id = response_body.first["_id"]

        @logger.debug("#{self.to_s}: sending state: #{status}")
        case status
          when "rejected", "invalid"
            state = Email::Status::TRY_AGAIN
          when "sent"
            state = Email::Status::SENT
          else
            state = Email::Status::SENDING
        end
      end
    end

    return [state, id, self.to_s]
  end

  def send_single_message
    parsed_address_list = Mail::AddressList.new(email_params[:to])
    attachment_string = email_params[:attachment].map do |file|
      file.original_filename
    end.join(",\n") if email_params[:attachment]
  end

  def get_message_status(id)
    @logger.debug("#{self.to_s}: Get message status of #{id}")
    json = {"key" => @key, "id" => id}
    response = HttpUtils.http_post(info_url, json.to_json, :content_type => @content_type)
    response_body = JSON.parse(response.body)

    @logger.debug("Post to #{info_url}")
    @logger.debug("Response Code: #{response.code}")

    if not response.code =~ /200/
      state = Email::Status::TRY_AGAIN
      if response_body["name"] == "Unknown_Message"
        # Since checking the message is asynchronous,
        # we might be querying for the message status
        # before the send request is out
        # Set to SENDING so that it will keep looping
        # in generic_email_provider
        state = Email::Status::UNKNOWN
      end
      @logger.debug("#{self.to_s}: Response body: #{response.body}")
    else
      if response_body["status"] =~ /error/i
        state = Email::Status::TRY_AGAIN
        @logger.debug("Response error: #{response_body["status"]}")
        @logger.debug("Response message: #{response_body["message"]}")

      else
        # From api docs
        # sending status of this message: sent, bounced, rejected
        status = response_body["state"]
        @logger.debug("Message state: #{status}")
        case status
          when "sent"
            state = Email::Status::SENT
          when "bounced", "rejected"
            state = Email::Status::TRY_AGAIN
          else
            state = Email::Status::SENDING
        end
      end
    end
    return [state, id, self.to_s]
  end


end