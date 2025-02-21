require 'email_spec/cucumber'
require 'rspec/core/pending'
require 'rspec/mocks'
require 'multi_test'
require 'faker'
require 'webdrivers/chromedriver'

# Monkey patch the webdrivers gem to handle name change as
# dependencies elsewhere prevent us from upgrading selenium
# https://github.com/titusfortner/webdrivers/issues/237
module Webdrivers
  Chromedriver.class_eval do
    def self.apple_filename(driver_version)
      if apple_m1_compatible?(driver_version)
        driver_version >= normalize_version('106.0.5249.61') ? 'mac_arm64' : 'mac64_m1'
      else
        'mac64'
      end
    end

    def self.driver_filename(driver_version)
      if System.platform == 'win' || System.wsl_v1?
        'win32'
      elsif System.platform == 'linux'
        'linux64'
      elsif System.platform == 'mac'
        apple_filename(driver_version)
      else
        raise 'Failed to determine driver filename to download for your OS.'
      end
    end
  end
end

MultiTest.disable_autorun

Capybara.javascript_driver = ENV.fetch("JS_DRIVER", "chrome_headless").to_sym
Capybara.default_max_wait_time = 5
Capybara.server_port = 3443
Capybara.app_host = "https://127.0.0.1:3443"
Capybara.default_host = "https://petition.parliament.uk"
Capybara.default_selector = :xpath
Capybara.automatic_label_click = true

Capybara.register_driver :chrome do |app|
  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: {
      args: [
        "allow-insecure-localhost",
        "window-size=1280,960",
        "proxy-server=127.0.0.1:8443"
      ],
      w3c: false
    },
    accept_insecure_certs: true
  )

  Capybara::Selenium::Driver.new(app, browser: :chrome, desired_capabilities: capabilities)
end

chromeArguments = %w[
  headless
  allow-insecure-localhost
  window-size=1280,960
  proxy-server=127.0.0.1:8443
]

if File.exist?("/.dockerenv")
  # Running as root inside Docker
  chromeArguments += %w[no-sandbox disable-gpu]
end

Capybara.register_driver :chrome_headless do |app|
  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: { args: chromeArguments, w3c: false },
    accept_insecure_certs: true
  )

  Capybara::Selenium::Driver.new(app, browser: :chrome, desired_capabilities: capabilities)
end

Capybara.register_server :epets do |app, port|
  Epets::SSLServer.build(app, port)
end

Capybara.server = :epets
Capybara.default_normalize_ws = true

pid = Process.spawn('bin/local_proxy', out: 'log/proxy.log', err: 'log/proxy.log')
Process.detach(pid)
at_exit { Process.kill('INT', pid) }

module CucumberI18n
  def t(*args)
    I18n.t(*args)
  end
end

module CucumberSanitizer
  def sanitize(html, options = {})
    @safe_list_sanitizer ||= Rails::Html::SafeListSanitizer.new
    @safe_list_sanitizer.sanitize(html, options).html_safe
  end

  def strip_tags(html)
    @full_sanitizer ||= Rails::Html::FullSanitizer.new
    @full_sanitizer.sanitize(html, encode_special_chars: false)
  end
end

module CucumberHelpers
  def click_details(name)
    if Capybara.current_driver == Capybara.javascript_driver
      page.find("//details/summary[contains(., '#{name}')]").click
    else
      page.find("//summary[contains(., '#{name}')]/..").click
    end
  end
end

World(CucumberI18n)
World(CucumberHelpers)
World(CucumberSanitizer)
World(MarkdownHelper)
World(RejectionHelper)
World(RSpec::Mocks::ExampleMethods)

# run background jobs inline with delayed job
ActiveJob::Base.queue_adapter = :delayed_job
Delayed::Worker.delay_jobs = false


# Monkey patch Cucumber::Rails to accept Capybara 3.x changes
# https://github.com/cucumber/cucumber-rails/commit/286f37f
module Cucumber
  module Rails
    module Capybara
      module JavascriptEmulation
        def click_with_javascript_emulation(*)
          if link_with_non_get_http_method?
            ::Capybara::RackTest::Form.new(driver, js_form(element_node.document, self[:href], emulated_method)).submit(self)
          else
            click_without_javascript_emulation
          end
        end
      end
    end
  end
end
