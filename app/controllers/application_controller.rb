class ApplicationController < ActionController::Base
  include FlashI18n

  protect_from_forgery with: :reset_session

  before_action :reload_site
  before_action :reload_parliament
  before_action :service_unavailable, unless: :site_enabled?
  before_action :authenticate, if: :site_protected?
  before_action :redirect_to_url_without_format, if: :unknown_format?

  before_action :set_seen_cookie_message, if: :show_cookie_message?
  helper_method :show_cookie_message?, :public_petition_facets

  after_action do
    directives = [
      "default-src 'self'",
      "connect-src 'self' https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com",
      "img-src 'self' https://*.google-analytics.com https://*.googletagmanager.com https://ssl.gstatic.com https://www.gstatic.com",
      "script-src 'self' 'unsafe-inline' https://*.googletagmanager.com https://tagmanager.google.com",
      "style-src 'self' 'unsafe-inline' https://tagmanager.google.com https://fonts.googleapis.com https://www.googletagmanager.com",
      "font-src 'self' 'unsafe-inline' https://fonts.gstatic.com data:"
    ]

    response.headers["Content-Security-Policy"] = directives.join("; ")
  end

  def admin_request?
    false
  end

  protected

  def authenticate
    authenticate_or_request_with_http_basic(Site.name) do |username, password|
      Site.authenticate(username, password)
    end
  end

  def csv_request?
    request.format.symbol == :csv
  end

  def json_request?
    request.format.symbol == :json
  end

  def unknown_format?
    request.format.nil?
  end

  def url_without_format
    URI.parse(request.original_url).tap do |uri|
      uri.path = File.join(File.dirname(request.path), File.basename(request.path, '.*'))
    end.to_s
  rescue URI::InvalidURIError => e
    home_url
  end

  def redirect_to_url_without_format
    redirect_to url_without_format
  end

  def reload_site
    Site.reload
  end

  def reload_parliament
    Parliament.reload
  end

  def service_unavailable
    raise Site::ServiceUnavailable, "Sorry, the website is temporarily unavailable"
  end

  def site_enabled?
    Site.enabled?
  end

  def site_protected?
    Site.protected? unless request.local?
  end

  def parliament_dissolved?
    Parliament.dissolved?
  end

  def redirect_to_home_page
    redirect_to home_url
  end

  def set_seen_cookie_message
    cookies[:seen_cookie_message] = { value: 'yes', expires: 1.year.from_now, httponly: true }
  end

  def set_cors_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'GET'
    headers['Access-Control-Allow-Headers'] = 'Origin, X-Requested-With, Content-Type, Accept'
  end

  def show_cookie_message?
    @show_cookie_message ||= cookies[:seen_cookie_message] != 'yes'
  end

  def public_petition_facets
    I18n.t('public', scope: :"petitions.facets")
  end

  def do_not_cache
    response.headers['Cache-Control'] = 'no-store'
  end

  def current_time
    Time.current.getutc.iso8601
  end
end
