require 'net/http'
require 'logger'

class HttpUtils
  def self.set_log(log = nil)
    @@log = log || Logger.new(STDOUT)
  end

  def self.http_post(url_string, body, opts={})
    uri = URI::parse(url_string)
    http_handle = Net::HTTP.new(uri.host, uri.port)
    http_handle.use_ssl = uri.scheme == 'https'
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(uri.user, uri.password)
    request.content_length = body.size
    request.body = body
    # for mailgun #"multipart/form-data; boundary=#{multipart_form_data_boundary}"
    request.content_type = opts[:content_type]
    # for mandrill "application/json"
    response = http_handle.start { |http| http.request(request) }
    return response
  end

  def self.http_get(url_string, params, opts={})
    full_url = url_string + '?' + URI.encode_www_form(params)
    uri = URI(full_url)

    req = Net::HTTP::Get.new(uri)
    req.basic_auth uri.user, uri.password
    res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https' ){|http|
      http.request(req)
    }
    return res
  end
end