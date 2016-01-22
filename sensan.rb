require 'active_support'
require 'active_support/core_ext'
require 'ruboty'
require 'capybara'
require 'capybara/poltergeist'
require 'faraday'
require 'open-uri'
require 'nokogiri'

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

class Nekogiri
  class NekoError < StandardError; end
  def initialize(url)
    charset = nil
    html = open(url) do |io|
      charset = io.charset
      io.read
    end
    @document = Nokogiri::HTML.parse(html, nil, charset)
  end

  def first_node(options = {}, &block)
    node =
      if options.key?(:xpath)
        @document.xpath(options[:xpath])[0]
      elsif options.key?(:css)
        @document.css(options[:css])[0]
      else
        raise ArgumentError
      end

    block.call(node) if block_given? rescue raise NekoError
  rescue NekoError
    'えらー！'
  end
end

module Forecast
  MY_GYAZO = 'http://gyazo.send.sh'.freeze
  TARGET_PAGE = 'http://weather.yahoo.co.jp/weather/jp/13/4410/13103.html'.freeze
  NOW_PAGE = 'http://www.tenki.jp/forecast/3/16/4410/13103.html'.freeze
  XPATHS = {
    temp: '//table[@class="live_point_amedas_ten_summary_entries"]/tr/td[@class="temp_entry"]',
    precip: '//table[@class="live_point_amedas_ten_summary_entries"]/tr/td[@class="precip_entry"]'
  }.freeze
  SELECTORS = {
    today: 'div#yjw_pinpoint_today',
    tomorrow: 'div#yjw_pinpoint_tomorrow',
    weekly: 'div#yjw_week',
  }.freeze

  def self.now
    doc = Nekogiri.new(NOW_PAGE)
    temp = doc.first_node(xpath: XPATHS[:temp]) { |node| "#{node.text.strip} ど" }
    precip = doc.first_node(xpath: XPATHS[:precip]) do |node|
      (node.text.strip.to_f > 0.0) ?  'あめめ！' : 'ふってない！'
    end

    "#{temp}\t#{precip}"
  end

  def self.today
    GyazoSpector.new(site: MY_GYAZO).capture(
      TARGET_PAGE, selector: SELECTORS[:today]
    ).upload!
  end

  def self.tomorrow
    GyazoSpector.new(site: MY_GYAZO).capture(
      TARGET_PAGE, selector: SELECTORS[:tomorrow]
    ).upload!
  end

  def self.weekly
    GyazoSpector.new(site: MY_GYAZO).capture(
      TARGET_PAGE, selector: SELECTORS[:weekly]
    ).upload!
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
          when /いまの|今の/ then Forecast.now
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
    end
  end
end
