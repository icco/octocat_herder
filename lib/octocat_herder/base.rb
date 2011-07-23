require 'cgi'
require 'link_header'
require 'parsedate'
require 'uri'

require 'octocat_herder/connection'

class OctocatHerder
  # This provides most of the functionality to interact with the
  # GitHub v3 API.
  module Base
    # The re-hydrated JSON retrieved from the GitHub API.
    attr_reader :raw

    # Our OctocatHerder::Connection, so we can make more requests
    # based on the information we retrieved from the GitHub API.
    attr_reader :connection

    # This isn't meant to be consumed publicly.  It's meant to be used
    # by the various class and instance methods that actually make the
    # API requests.
    #
    # [+raw_hash+] The re-hydrated JSON received from the GitHub API via OctocatHerder::Connection.
    #
    # [+conn+] An instance of OctocatHerder::Connection.  Can be left off to make unauthenticated requests.
    def initialize(raw_hash, conn = OctocatHerder::Connection.new)
      @connection = conn
      @raw = raw_hash
    end

    # We use the +method_missing+ magic to create accessors for the
    # information we got back from the GitHub API.  You can get a list
    # of all of the available things from #available_attributes.
    def method_missing(id, *args)
      unless @raw and @raw.keys.include?(id.id2name)
        raise NoMethodError.new("undefined method #{id.id2name} for #{self}:#{self.class}")
      end

      @raw[id.id2name]
    end

    # This returns a list of the things that the API request returned
    # to us.
    def available_attributes
      attrs = []
      attrs += @raw.keys.reject do |k|
        [
          'id',
          'type',
        ].include? k
      end if @raw

      (attrs + additional_attributes).uniq
    end

    private

    # This is intended to be used by the various classes implementing
    # the GitHub API end-points.
    #
    # [conn] An instance of OctocatHerder::Connection to use for the request.
    # [end_point] The part of the API URL after 'https://api.github.com', including the leading '/'.
    # [options] A Hash of options to be passed down to HTTParty, and additionally +:paginated+ to let us know if we should be retrieving _all_ pages of a paginated result and +:params+ which will be constructed into a query string using OctocatHerder::Base.query_string_from_params.
    def self.raw_get(conn, end_point, options={})
      paginated    = options.delete(:paginated)
      query_params = options.delete(:params) || {}

      query_params[:per_page] = 100 if paginated and query_params[:per_page].nil?
      query_string = query_string_from_params(query_params)

      result = conn.get(end_point + query_string, options)
      raise "Unable to retrieve #{end_point}" unless result

      full_result = result.parsed_response

      if paginated
        if next_page = page_from_headers(result.headers, 'next')
          query_params[:page] = next_page

          new_options = options.merge(query_params)
          new_options[:paginated] = true

          full_result += raw_get(conn, end_point, new_options)
        end
      end

      full_result
    end

    # Given the link header as +headers+, and the type of link to
    # retrieve as +type+, return the page that +type+ links to.
    #
    # Possible values for +type+ are:
    # [next] Shows the URL of the immediate next page of results.
    # [last] Shows the URL of the last page of results.
    # [first] Shows the URL of the first page of results.
    # [prev] Shows the URL of the immediate previous page of results.
    def self.page_from_headers(headers, type)
      link = LinkHeader.parse(headers['link']).find_link(['rel', type])
      return unless link

      CGI.parse(URI.parse(link.href).query)['page'].first
    end

    # Convenience method to generate URL query strings.
    #
    # [+params+] A Hash of key/values to be turned into a URL query string.  Does not support nested data.
    def self.query_string_from_params(params)
      return '' if params.keys.empty?

      '?' + params.map {|k,v| "#{URI.escape("#{k}")}=#{URI.escape("#{v}")}"}.join('&')
    end

    # Intended to be overridden in classes using OctocatHerder::Base,
    # so they can make the methods they define show up in
    # #available_attributes.
    def additional_attributes
      []
    end

    def parse_date_time(date_time)
      return nil unless date_time

      Time.utc(*ParseDate.parsedate(date_time))
    end
  end
end
