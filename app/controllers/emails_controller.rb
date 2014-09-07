require 'securerandom'
require "net/http"
require "uri"
require 'mail'
require 'pp'

class EmailsController < ApplicationController
  before_action :set_email, only: [:show, :edit, :update, :destroy]

  # GET /emails
  # GET /emails.json
  def index
    @emails = Email.all
  end

  # GET /emails/1
  # GET /emails/1.json
  def show
  end

  # GET /emails/new
  def new
    @email = Email.new
  end

  # GET /emails/1/edit
  def edit
  end

  # POST /emails
  # POST /emails.json
  def create
    # @attachment_location = Rails.root.join('public', 'uploads').to_s
    #
    # attachments = email_params[:attachment]
    # if attachments
    #   @file_id = Time.now.to_i.to_s
    #   attachments.map do |a|
    #     File.open(File.join(@attachment_location, @file_id + a.original_filename), 'wb') do |file|
    #       file.write(a.read)
    #     end
    #   end
    # end

    parsed_address_list = Mail::AddressList.new(email_params[:to])
    attachment_string = email_params[:attachment].map do |file|
      file.original_filename
    end.join(",\n") if email_params[:attachment]

    separate_emails = parsed_address_list.addresses.map do |a|
      email = email_params
      email[:to] = a.to_s
      email[:attachment] = attachment_string
      #email[:attachment_id] = @file_id
      @email = Email.create(email)
      api_params = email_params
      api_params[:to] = a.to_s

      GenericEmailProvider.new.send_message(api_params, @email)
    end


    # email_provider_config = HashWithIndifferentAccess.new(YAML.load(File.open("#{Rails.root.to_s}/config/email_provider.yml")))
    # email_params_copy = email_params
    # mandrill_api = MandrillApi.new(email_provider_config[:mandrill])
    # body = mandrill_api.create_send_message_body(email_params)
    # uri = URI::parse(mandrill_api.send_message_url)

    respond_to do |format|
      if @email.save
        format.html { redirect_to @email, notice: 'Email was successfully created.' }
        format.json { render :show, status: :created, location: @email }
      else
        format.html { render :new }
        format.json { render json: @email.errors, status: :unprocessable_entity }
      end
    end
  end

# PATCH/PUT /emails/1
# PATCH/PUT /emails/1.json
  def update
    puts "attachment is"
    puts params[:email][:attachment]

    respond_to do |format|
      if @email.update(email_params)
        format.html { redirect_to @email, notice: 'Email was successfully updated.' }
        format.json { render :show, status: :ok, location: @email }
      else
        format.html { render :edit }
        format.json { render json: @email.errors, status: :unprocessable_entity }
      end
    end
  end

# DELETE /emails/1
# DELETE /emails/1.json
  def destroy
    @email.destroy
    respond_to do |format|
      format.html { redirect_to emails_url, notice: 'Email was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
# Use callbacks to share common setup or constraints between actions.
  def set_email
    @email = Email.find(params[:id])
  end

# Never trust parameters from the scary internet, only allow the white list through.
  def email_params
    params.require(:email).permit(:to, :subject, :body, :attachment => [])
  end

################## MAILGUN #########################
  def multipart_form_data_boundary
    @form_boundary ||= SecureRandom::hex.to_s + "MultipartFormDataBoundary"
    return @form_boundary
  end

  def multipart_mixed_boundary
    @mixed_boundary ||= SecureRandom::hex.to_s + "MultipartMixedBoundary"
    return @mixed_boundary
  end

# def multipart_mixed_content_type_string
#   "Content-Type: multipart/mixed; boundary=#{multipart_mixed_boundary}"
# end

  def form_data_key_value_string(hash)
    string = ""
    hash.each do |key, value|
      string += "--#{multipart_form_data_boundary}\r\n" +
          "Content-Disposition: form-data; name=\"#{key}\"\r\n" +
          "\r\n" +
          "#{value}\r\n"
    end
    return string
  end

  def single_file_form_data_string(file, index=nil)
    headers = file.headers.split(';')
    headers[1] = " name=\"attachment[]\""
    headers = headers.join(';')

    string = "--" + multipart_form_data_boundary + "\r\n" + headers +
        "\r\n"
    puts string
    string += "#{file.read}"
    return string
  end

  def multiple_file_form_data_string(files)
    string = ""
    files.each_with_index do |file, index|
      string += single_file_form_data_string(file, index)
    end

=begin
    headers = files.first.headers.split(';')[0..1]
    headers[1] = " name=\"attachment\""
    headers = headers.join(';')
    string = headers + "\r\n"
    string += multipart_mixed_content_type_string + "\r\n\r\n"
    files.collect do |file|
      file_string = "--" + multipart_mixed_boundary + "\r\n" +
          "Content-Disposition: file; filename=\"#{file.original_filename}\"\r\n" +
          "Content-Type: #{file.content_type}\r\n" +
          "\r\n"
      puts file_string
      file_string += "#{file.read}"
      string += file_string
    end
    string += "\r\n--#{multipart_mixed_boundary}--"
=end
    return string
  end

  def create_mailgun_email_params(email_params)
    mailgun_params = email_params
    mailgun_params[:from] = "postmaster@sandbox5550f9437950483eb57f7a6daa2c8f13.mailgun.org"
    mailgun_params[:text] = email_params[:body]
    mailgun_params.delete(:attachment)
    mailgun_params.delete(:body)
    return mailgun_params
  end



  def create_mailgun_email_body(email_params)
    attachments = email_params[:attachment]
    attachments_body = if attachments
                         attachments.collect { |file| single_file_form_data_string(file) }.join('')
                         # if attachments.size > 1
                         #   multiple_file_form_data_string(attachments)
                         # else
                         #   single_file_form_data_string(attachments.first)
                         # end
                       else
                         ""
                       end
    body = form_data_key_value_string(create_mailgun_email_params(email_params))

    body += attachments_body + "\r\n--#{multipart_form_data_boundary}--\r\n"

    puts "body: \n #{body}"
    body
  end

  def create_mandrill_email_body(email_params)
    parsed_address_list = Mail::AddressList.new(email_params[:to])

    addresses = parsed_address_list.addresses.map do |a|
      address = {}
      address["email"] = a.address
      address["name"] = a.display_name if a.display_name.present?
      address
    end

    attachments = email_params[:attachment]
    attachments = if attachments
                    attachments.map do |a|
                      hash = {}
                      hash["type"] = a.content_type
                      hash["name"] = a.original_filename
                      content = a.read
                      encoded_content = Base64.encode64(content)
                      hash["content"] = encoded_content
                      hash
                    end
                  else
                    []
                  end

    json_body = {"key" => "P0MmT5x_lJb5Di0kw45B5Q",
                 "message" =>
                     {
                         "text" => "#{email_params[:body]}",
                         "subject" => "#{email_params[:subject]}",
                         "from_email" => "postmaster@sandbox5550f9437950483eb57f7a6daa2c8f13.mailgun.org",
                         "from_name" => "Post Master",
                         "to" => addresses,
                         "attachments" => attachments
                     }
    }


    return json_body.to_json
  end


end
