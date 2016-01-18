require 'active_support'
require 'active_support/core_ext'
require 'ruboty'
require 'capybara'
require 'capybara/poltergeist'
require 'faraday'

class GyazoSpector
  CONTENT_TYPE = 'image/png'.freeze
  DEFAULT_SITE = 'http://gyazo.com'.freeze
  DEFAULT_ENDPOINT = '/'.freeze
  DEFAULT_POLTERGEIST_OPTIONS = {
    js_errors: false,
    timeout: 1000,
    debug: false
  }.freeze
  DEFAULT_SELECTOR = :css

  attr_reader :site, :endpoint, :session, :imagedata

  def initialize(opts = {})
    @site = opts.delete(:site) || DEFAULT_SITE
    @endpoint = opts.delete(:endpoint) || DEFAULT_ENDPOINT
    Capybara.default_selector = opts.delete(:selector) || DEFAULT_SELECTOR

    options = DEFAULT_POLTERGEIST_OPTIONS.merge(opts)
    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app, options)
    end
  end

  def session
    @session ||= Capybara::Session.new(:poltergeist)
  end

  def capture(url, options = {})
    session.visit(url)
    @imagedata = Base64.decode64(session.driver.render_base64(:png, options))
    self
  end

  def upload!
    connection = Faraday.new(site) do |client|
      client.request :multipart
      client.request :url_encoded
      client.adapter Faraday.default_adapter
    end
    payload = { 
      imagedata: Faraday::UploadIO.new(StringIO.new(imagedata), CONTENT_TYPE)
    }
    connection.post(endpoint, payload).body
  end
end

module Ruboty
  module Handlers
    class Sensan < Base
      BIRTH_DAY = Date.new(2012, 05 ,05).freeze

      on /(?<text>.+)/, name: :generic, description: 'generic action'

      def generic(message)
        handle_message(message)
      end

      private

      def handle_message(message)
        case message[:text]
        when /ping/i then do_nothing
        when /てんき|天気/ then weather(message)
        when /\A(?:何歳|なんさい|いくつ)(?:になったの)?(?:\?|？)/ then how_old(message)
        else
          default_action(message)
        end
      end

      def how_old(message)
        age = (Date.current.to_s(:number).to_i - BIRTH_DAY.to_s(:number).to_i) / 10000
        message.reply("#{age} さい！")
      end

      def weather(message)
        response = "にゃー\n"
        response <<
          case message[:text]
          when /きょうの|今日の/ then Forecast.today
          when /あしたの|明日の/ then Forecast.tomorrow
          else Forecast.weekly
          end

        message.reply(response)
      end

      def default_action(message)
        message.reply('にゃー')
      end

      def do_nothing
        nil
      end

      module Forecast
        MY_GYAZO = 'http://gyazo.send.sh'
        TARGET_PAGE = 'http://weather.yahoo.co.jp/weather/jp/13/4410/13103.html'

        def self.today
          GyazoSpector.new(site: MY_GYAZO).capture(
            TARGET_PAGE,
            selector: 'div#yjw_pinpoint_today',
          ).upload!
        end

        def self.tomorrow
          GyazoSpector.new(site: MY_GYAZO).capture(
            TARGET_PAGE,
            selector: 'div#yjw_pinpoint_tomorrow',
          ).upload!
        end

        def self.weekly
          GyazoSpector.new(site: MY_GYAZO).capture(
            TARGET_PAGE,
            selector: 'div#yjw_week',
          ).upload!
        end
      end
    end
  end
end
