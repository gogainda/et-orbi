
require 'date' if RUBY_VERSION < '1.9.0'
require 'time'

require 'tzinfo'

require 'et-orbi/zone_aliases'


module EtOrbi

  VERSION = '1.1.7'

  #
  # module methods

  class << self

    def now(zone=nil)

      EoTime.new(Time.now.to_f, zone)
    end

    def parse(str, opts={})

#      if defined?(::Chronic) && t = ::Chronic.parse(str, opts)
#        return EoTime.new(t, nil)
#      end

      begin
        DateTime.parse(str)
      rescue
        fail ArgumentError, "No time information in #{str.inspect}"
      end
      #end if RUBY_VERSION < '1.9.0'
      #end if RUBY_VERSION < '2.0.0'
        #
        # is necessary since Time.parse('xxx') in Ruby < 1.9 yields `now`

      str_zone = get_tzone(list_iso8601_zones(str).last)

      zone =
        opts[:zone] ||
        str_zone ||
        find_olson_zone(str) ||
        determine_local_tzone

      str = str.sub(zone.name, '') unless zone.name.match(/\A[-+]/)
        #
        # for 'Sun Nov 18 16:01:00 Asia/Singapore 2012',
        # although where does rufus-scheduler have it from?

      local = Time.parse(str)

      secs =
        if str_zone
          local.to_f
        else
          zone.local_to_utc(local).to_f
        end

      EoTime.new(secs, zone)
    end

    def make_time(*a)

      zone = a.length > 1 ? get_tzone(a.last) : nil
      a.pop if zone

      o = a.length > 1 ? a : a.first

      case o
      when Time then make_from_time(o, zone)
      when Date then make_from_date(o, zone)
      when Array then make_from_array(o, zone)
      when String then make_from_string(o, zone)
      when Numeric then make_from_numeric(o, zone)
      when ::EtOrbi::EoTime then make_from_eotime(o, zone)
      else fail ArgumentError.new(
        "Cannot turn #{o.inspect} to a ::EtOrbi::EoTime instance")
      end
    end

    def make_from_time(t, zone)

      z =
        zone ||
        get_as_tzone(t) ||
        get_tzone(t.zone) ||
        get_local_tzone(t)

      z ||= t.zone
        # pass the abbreviation anyway,
        # it will be used in the resulting error message

      EoTime.new(t, z)
    end

    def make_from_date(d, zone)

      make_from_time(
        d.respond_to?(:to_time) ?
        d.to_time :
        Time.parse(d.strftime('%Y-%m-%d %H:%M:%S')),
        zone)
    end

    def make_from_array(a, zone)

      t = Time.utc(*a)
      s = t.strftime("%Y-%m-%d %H:%M:%S.#{'%06d' % t.usec}")

      make_from_string(s, zone)
    end

    def make_from_string(s, zone)

      parse(s, zone: zone)
    end

    def make_from_numeric(f, zone)

      EoTime.new(Time.now.to_f + f, zone)
    end

    def make_from_eotime(eot, zone)

      return eot if zone == nil || zone == eot.zone
      EoTime.new(eot.to_f, zone)
    end

    def get_tzone(o)

      return o if o.is_a?(::TZInfo::Timezone)
      return nil if o == nil
      return determine_local_tzone if o == :local
      return ::TZInfo::Timezone.get('Zulu') if o == 'Z'
      return o.tzinfo if o.respond_to?(:tzinfo)

      o = to_offset(o) if o.is_a?(Numeric)

      return nil unless o.is_a?(String)

      s = unalias(o)

      get_offset_tzone(s) ||
      (::TZInfo::Timezone.get(s) rescue nil)
    end

    def render_nozone_time(seconds)

      t =
        Time.utc(1970) + seconds
      ts =
        t.strftime('%Y-%m-%d %H:%M:%S') +
        ".#{(seconds % 1).to_s.split('.').last}"
      tz =
        EtOrbi.determine_local_tzone
      z =
        tz ? tz.period_for_local(t).abbreviation.to_s : nil

      "(secs:#{seconds},utc~:#{ts.inspect},ltz~:#{z.inspect})"
    end

    def tzinfo_version

      #TZInfo::VERSION
      Gem.loaded_specs['tzinfo'].version.to_s
    rescue => err
      err.inspect
    end

    def tzinfo_data_version

      #TZInfo::Data::VERSION rescue nil
      Gem.loaded_specs['tzinfo-data'].version.to_s rescue nil
    end

    def platform_info

      etos = Proc.new { |k, v| "#{k}:#{v.inspect}" }

      h = {
        'etz' => ENV['TZ'],
        'tnz' => Time.now.zone,
        'tziv' => tzinfo_version,
        'tzidv' => tzinfo_data_version,
        'rv' => RUBY_VERSION,
        'rp' => RUBY_PLATFORM,
        'win' => Gem.win_platform?,
        'rorv' => (Rails::VERSION::STRING rescue nil),
        'astz' => ([ Time.zone.class, Time.zone.tzinfo.name ] rescue nil),
        'eov' => EtOrbi::VERSION,
        'eotnz' => '???',
        'eotnfz' => '???',
        'eotlzn' => '???' }
      if ltz = EtOrbi::EoTime.local_tzone
        h['eotnz'] = EtOrbi::EoTime.now.zone
        h['eotnfz'] = EtOrbi::EoTime.now.strftime('%z')
        h['eotlzn'] = ltz.name
      end

      "(#{h.map(&etos).join(',')},#{gather_tzs.map(&etos).join(',')})"
    end

    alias make make_time

    # For `make info`
    #
    def _make_info

      puts render_nozone_time(Time.now.to_f)
      puts platform_info
    end

    protected

    def get_local_tzone(t)

      l = Time.local(t.year, t.month, t.day, t.hour, t.min, t.sec, t.usec)

      (t.zone == l.zone) ? determine_local_tzone : nil
    end

    def get_as_tzone(t)

      t.respond_to?(:time_zone) ? t.time_zone : nil
    end
  end

  # Our EoTime class (which quacks like a ::Time).
  #
  # An EoTime instance should respond to most of the methods ::Time instances
  # respond to. If a method is missing, feel free to open an issue to
  # ask (politely) for it. If it makes sense, it'll get added, else
  # a workaround will get suggested.
  # The immediate workaround is to call #to_t on the EoTime instance to get
  # equivalent ::Time instance in the local, current, timezone.
  #
  class EoTime

    #
    # class methods

    class << self

      def now(zone=nil)

        EtOrbi.now(zone)
      end

      def parse(str, opts={})

        EtOrbi.parse(str, opts)
      end

      def get_tzone(o)

        EtOrbi.get_tzone(o)
      end

      def local_tzone

        EtOrbi.determine_local_tzone
      end

      def platform_info

        EtOrbi.platform_info
      end

      def make(o)

        EtOrbi.make_time(o)
      end

      def utc(*a)

        EtOrbi.make_from_array(a, EtOrbi.get_tzone('UTC'))
      end

      def local(*a)

        EtOrbi.make_from_array(a, local_tzone)
      end
    end

    #
    # instance methods

    attr_reader :seconds
    attr_reader :zone

    def initialize(s, zone)

      @seconds = s.to_f
      @zone = self.class.get_tzone(zone || :local)

      fail ArgumentError.new(
        "Cannot determine timezone from #{zone.inspect}" +
        "\n#{EtOrbi.render_nozone_time(@seconds)}" +
        "\n#{EtOrbi.platform_info.sub(',debian:', ",\ndebian:")}" +
        "\nTry setting `ENV['TZ'] = 'Continent/City'` in your script " +
        "(see https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)" +
        (defined?(TZInfo::Data) ? '' : "\nand adding gem 'tzinfo-data'")
      ) unless @zone

      @time = nil
        # cache for #to_time result
    end

    def seconds=(f)

      @time = nil
      @seconds = f
    end

    def zone=(z)

      @time = nil
      @zone = self.class.get_tzone(zone || :current)
    end

    # Returns true if this EoTime instance corresponds to 2 different UTC
    # times.
    # It happens when transitioning from DST to winter time.
    #
    # https://www.timeanddate.com/time/change/usa/new-york?year=2018
    #
    def ambiguous?

      @zone.local_to_utc(@zone.utc_to_local(utc))

      false

    rescue TZInfo::AmbiguousTime

      true
    end

    # Returns this ::EtOrbi::EoTime as a ::Time instance
    # in the current UTC timezone.
    #
    def utc

      Time.utc(1970) + @seconds
    end

    # Returns true if this ::EtOrbi::EoTime instance timezone is UTC.
    # Returns false else.
    #
    def utc?

      %w[ gmt utc zulu etc/gmt etc/utc ].include?(
        @zone.canonical_identifier.downcase)
    end

    alias getutc utc
    alias getgm utc
    alias to_utc_time utc

    def to_f

      @seconds
    end

    def to_i

      @seconds.to_i
    end

    def strftime(format)

      format = format.gsub(/%(\/?Z|:{0,2}z)/) { |f| strfz(f) }

      to_time.strftime(format)
    end

    # Returns this ::EtOrbi::EoTime as a ::Time instance
    # in the current timezone.
    #
    # Has a #to_t alias.
    #
    def to_local_time

      Time.at(@seconds)
    end

    alias to_t to_local_time

    def is_dst?

      @zone.period_for_utc(utc).std_offset != 0
    end
    alias isdst is_dst?

    def to_debug_s

      uo = self.utc_offset
      uos = uo < 0 ? '-' : '+'
      uo = uo.abs
      uoh, uom = [ uo / 3600, uo % 3600 ]

      [
        'ot',
        self.strftime('%Y-%m-%d %H:%M:%S'),
        "%s%02d:%02d" % [ uos, uoh, uom ],
        "dst:#{self.isdst}"
      ].join(' ')
    end

    def utc_offset

      @zone.period_for_utc(utc).utc_offset
    end

    %w[
      year month day wday hour min sec usec asctime
    ].each do |m|
      define_method(m) { to_time.send(m) }
    end

    def ==(o)

      o.is_a?(EoTime) &&
      o.seconds == @seconds &&
      (o.zone == @zone || o.zone.current_period == @zone.current_period)
    end
    #alias eql? == # FIXME see Object#== (ri)

    def >(o); @seconds > _to_f(o); end
    def >=(o); @seconds >= _to_f(o); end
    def <(o); @seconds < _to_f(o); end
    def <=(o); @seconds <= _to_f(o); end
    def <=>(o); @seconds <=> _to_f(o); end

    def add(t); @time = nil; @seconds += t.to_f; self; end
    def subtract(t); @time = nil; @seconds -= t.to_f; self; end

    def +(t); inc(t, 1); end
    def -(t); inc(t, -1); end

    WEEK_S = 7 * 24 * 3600

    def monthdays

      date = to_time

      pos = 1
      d = self.dup

      loop do
        d.add(-WEEK_S)
        break if d.month != date.month
        pos = pos + 1
      end

      neg = -1
      d = self.dup

      loop do
        d.add(WEEK_S)
        break if d.month != date.month
        neg = neg - 1
      end

      [ "#{date.wday}##{pos}", "#{date.wday}##{neg}" ]
    end

    def to_s

      strftime('%Y-%m-%d %H:%M:%S %z')
    end

    def to_zs

      strftime('%Y-%m-%d %H:%M:%S %/Z')
    end

    def iso8601(fraction_digits=0)

      s = (fraction_digits || 0) > 0 ? ".%#{fraction_digits}N" : ''
      strftime("%Y-%m-%dT%H:%M:%S#{s}%:z")
    end

    # Debug current time by showing local time / delta / utc time
    # for example: "0120-7(0820)"
    #
    def to_utc_comparison_s

      per = @zone.period_for_utc(utc)
      off = per.utc_total_offset

      off = off / 3600
      off = off >= 0 ? "+#{off}" : off.to_s

      strftime('%H%M') + off + utc.strftime('(%H%M)')
    end

    def to_time_s

      strftime("%H:%M:%S.#{'%06d' % usec}")
    end

    def inc(t, dir=1)

      case t
      when Numeric
        nt = self.dup
        nt.seconds += dir * t.to_f
        nt
      when ::Time, ::EtOrbi::EoTime
        fail ArgumentError.new(
          "Cannot add #{t.class} to EoTime") if dir > 0
        @seconds + dir * t.to_f
      else
        fail ArgumentError.new(
          "Cannot call add or subtract #{t.class} to EoTime instance")
      end
    end

    def localtime(zone=nil)

      EoTime.new(self.to_f, zone)
    end

    alias translate localtime

    def wday_in_month

      [ count_weeks(-1), - count_weeks(1) ]
    end

    def reach(points)

      t = EoTime.new(self.to_f, @zone)
      step = 1

      s = points[:second] || points[:sec] || points[:s]
      m = points[:minute] || points[:min] || points[:m]
      h = points[:hour] || points[:hou] || points[:h]

      fail ArgumentError.new("missing :second, :minute, and :hour") \
        unless s || m || h

      if !s && !m
        step = 60 * 60
        t -= t.sec
        t -= t.min * 60
      elsif !s
        step = 60
        t -= t.sec
      end

      loop do
        t += step
        next if s && t.sec != s
        next if m && t.min != m
        next if h && t.hour != h
        break
      end

      t
    end

    protected

    # Returns a Ruby Time instance.
    #
    # Warning: the timezone of that Time instance will be UTC when used with
    # TZInfo < 2.0.0.
    #
    def to_time

      @time ||= @zone.utc_to_local(utc)
    end

    def count_weeks(dir)

      c = 0
      t = self
      until t.month != self.month
        c += 1
        t += dir * (7 * 24 * 3600)
      end

      c
    end

    def strfz(code)

      return @zone.name if code == '%/Z'

      per = @zone.period_for_utc(utc)

      return per.abbreviation.to_s if code == '%Z'

      off = per.utc_total_offset
        #
      sn = off < 0 ? '-' : '+'; off = off.abs
      hr = off / 3600
      mn = (off % 3600) / 60
      sc = 0

      if @zone.name == 'UTC'
        'Z' # align on Ruby ::Time#iso8601
      elsif code == '%z'
        '%s%02d%02d' % [ sn, hr, mn ]
      elsif code == '%:z'
        '%s%02d:%02d' % [ sn, hr, mn ]
      else
        '%s%02d:%02d:%02d' % [ sn, hr, mn, sc ]
      end
    end

    def _to_f(o)

      fail ArgumentError(
        "Comparison of EoTime with #{o.inspect} failed"
      ) unless o.is_a?(EoTime) || o.is_a?(Time)

      o.to_f
    end
  end

  class << self

    #
    # extra public methods

    # https://en.wikipedia.org/wiki/ISO_8601
    # Postel's law applies
    #
    def list_iso8601_zones(s)

      s
        .scan(
          %r{
            (?<=:\d\d)
            \s*
            (?:
              [-+]
              (?:[0-1][0-9]|2[0-4])
              (?:(?::)?(?:[0-5][0-9]|60))?
              (?![-+])
              |
              Z
            )
          }x)
        .collect(&:strip)
    end

    def list_olson_zones(s)

      s
        .scan(
          %r{
            (?<=\s|\A)
            (?:[A-Z][A-Za-z0-9+_-]+)
            (?:\/(?:[A-Z][A-Za-z0-9+_-]+)){0,2}
          }x)
    end

    def find_olson_zone(str)

      list_olson_zones(str).each { |s| z = get_tzone(s); return z if z }
      nil
    end

    def determine_local_tzone

      # ENV has the priority

      etz = ENV['TZ']

      tz = etz && (::TZInfo::Timezone.get(etz) rescue nil)
      return tz if tz

      # then Rails/ActiveSupport has the priority

      if Time.respond_to?(:zone) && Time.zone.respond_to?(:tzinfo)
        tz = Time.zone.tzinfo
        return tz if tz
      end

      # then the operating system is queried

      tz = ::TZInfo::Timezone.get(os_tz) rescue nil
      return tz if tz

      # then Ruby's time zone abbs are looked at CST, JST, CEST, ... :-(

      tzs = determine_local_tzones
      tz = (etz && tzs.find { |z| z.name == etz }) || tzs.first
      return tz if tz

      # then, fall back to GMT offest :-(

      n = Time.now

      get_tzone(n.zone) ||
      get_tzone(n.strftime('%Z%z'))
    end
    alias zone determine_local_tzone

    attr_accessor :_os_zone # test tool

    def os_tz

      return (@_os_zone == '' ? nil : @_os_zone) \
        if defined?(@_os_zone) && @_os_zone

      @os_tz ||= (debian_tz || centos_tz || osx_tz)
    end

    # Semi-helpful, since it requires the current time
    #
    def windows_zone_name(zone_name, time)

      twin = Time.utc(time.year, 1, 1) # winter
      tsum = Time.utc(time.year, 7, 1) # summer

      tz = ::TZInfo::Timezone.get(zone_name)
      tzo = tz.period_for_local(time).utc_total_offset
      tzop = tzo < 0 ? nil : '-'; tzo = tzo.abs
      tzoh = tzo / 3600
      tzos = tzo % 3600
      tzos = tzos == 0 ? nil : ':%02d' % (tzos / 60)

      abbs = [
        tz.period_for_utc(twin).abbreviation.to_s,
        tz.period_for_utc(tsum).abbreviation.to_s ]
          .uniq

      if abbs[0].match(/\A[A-Z]/)
        [ abbs[0], tzop, tzoh, tzos, abbs[1] ].compact.join
      else
        [ tzop, tzoh, tzos || ':00' ].collect(&:to_s).join
      end
    end

    #
    # protected module methods

    protected

    def to_offset(n)

      i = n.to_i
      sn = i < 0 ? '-' : '+'; i = i.abs
      hr = i / 3600; mn = i % 3600; sc = i % 60

      sc > 0 ?
        '%s%02d:%02d:%02d' % [ sn, hr, mn, sc ] :
        '%s%02d:%02d' % [ sn, hr, mn ]
    end

    def get_offset_tzone(str)

      # custom timezones, no DST, just an offset, like "+08:00" or "-01:30"

      m = str.match(/\A([+-][0-1][0-9]):?([0-5][0-9])?\z/) rescue nil
        #
        # On Windows, the real encoding could be something other than UTF-8,
        # and make the match fail
        #
      return nil unless m

      hr = m[1].to_i
      mn = m[2].to_i

      hr = nil if hr.abs > 11
      hr = nil if mn > 59
      mn = -mn if hr && hr < 0

      return (
        (@custom_tz_cache ||= {})[str] =
          create_offset_tzone(hr * 3600 + mn * 60, str)
      ) if hr

      nil
    end

    if defined? TZInfo::DataSources::ConstantOffsetDataTimezoneInfo
      # TZInfo >= 2.0.0

      def create_offset_tzone(utc_off, id)

        off = TZInfo::TimezoneOffset.new(utc_off, 0, id)
        tzi = TZInfo::DataSources::ConstantOffsetDataTimezoneInfo.new(id, off)
        tzi.create_timezone
      end

    else
      # TZInfo < 2.0.0

      def create_offset_tzone(utc_off, id)

        tzi = TZInfo::TransitionDataTimezoneInfo.new(id)
        tzi.offset(id, utc_off, 0, id)
        tzi.create_timezone
      end
    end

    def determine_local_tzones

      tabbs = (-6..5)
        .collect { |i|
          t = Time.now + i * 30 * 24 * 3600
          "#{t.zone}_#{t.utc_offset}" }
        .uniq
        .sort
        .join('|')

      t = Time.now
      #tu = t.dup.utc # /!\ dup is necessary, #utc modifies its target

      twin = Time.local(t.year, 1, 1) # winter
      tsum = Time.local(t.year, 7, 1) # summer

      @tz_all ||= ::TZInfo::Timezone.all
      @tz_winter_summer ||= {}

      @tz_winter_summer[tabbs] ||= @tz_all
        .select { |tz|
          pw = tz.period_for_local(twin)
          ps = tz.period_for_local(tsum)
          tabbs ==
            [ "#{pw.abbreviation}_#{pw.utc_total_offset}",
              "#{ps.abbreviation}_#{ps.utc_total_offset}" ]
              .uniq.sort.join('|') }

      @tz_winter_summer[tabbs]
    end

    #
    # system tz determination

    def debian_tz

      path = '/etc/timezone'

      File.exist?(path) ? File.read(path).strip : nil
    rescue; nil; end

    def centos_tz

      path = '/etc/sysconfig/clock'

      File.open(path, 'rb') do |f|
        until f.eof?
          if m = f.readline.match(/ZONE="([^"]+)"/); return m[1]; end
        end
      end if File.exist?(path)

      nil
    rescue; nil; end

    def osx_tz

      path = '/etc/localtime'

      File.symlink?(path) ?
        File.readlink(path).split('/')[4..-1].join('/') :
        nil
    rescue; nil; end

    def gather_tzs

      { :debian => debian_tz, :centos => centos_tz, :osx => osx_tz }
    end
  end
end

