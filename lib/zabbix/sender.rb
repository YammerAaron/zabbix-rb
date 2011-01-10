class Zabbix::Sender

  DEFAULT_SERVER_PORT = 10051

  attr_reader :configured 

  def initialize(opts={})
    if opts[:config_file]
      config = Zabbix::Agent::Configuration.read(opts[:config_file])
      @host  = config.server
      @port  = config.server_port || DEFAULT_SERVER_PORT
    end

    if opts[:host]
      @host = opts[:host]
      @port = opts[:port] || DEFAULT_SERVER_PORT
    end

  end


  def configured?
    @configured ||= !(@host.nil? and @port.nil?)
  end


  def connect
    @socket ||= TCPSocket.new(@host, @port)
  end

  def disconnect
    if @socket
      @socket.close unless @socket.closed?
      @socket = nil 
    end
    return true
  end

  def send_start(key, opts={})
    send_data("#{key}.start", 1, opts)
  end


  def send_stop(key, opts={}) 
    send_data("#{key}.stop", 1, opts)
  end


  def send_heartbeat(key, msg="", opts={})
    send_data("#{key}.heartbeat", msg, opts)
  end

  def send_data(key, value, opts={})
    return false unless configured? 
    host  = opts[:host]
    clock = opts[:ts  ]
    return send_zabbix_request([ cons_zabbix_data_element(host, key, value, clock) ])
  end  

  private 

  def cons_zabbix_data_element(host, key, value, clock=Time.now.to_i)
    return {
      :host  => host, 
      :key   => key, 
      :value => value,
      :clock => clock
    }
  end

  def dryrun_zabbix_request(data)
    request = Yajl::Encoder.encode({
      :request => 'agent data' ,
      :clock   => Time.now.to_i,
      :data    => data
    },:pretty => true)
    puts "#{request}"
  end


  def send_zabbix_request(data)
    status  = false
    request = Yajl::Encoder.encode({
      :request => 'agent data' ,
      :clock   => Time.now.to_i,
      :data    => data
    })

    begin 
      sock = connect
      sock.write "ZBXD\x01"
      sock.write [request.size].pack('q')
      sock.write request 
      sock.flush

      # FIXME: check header to make sure it's the message we expect?
      header   = sock.read(5)
      len      = sock.read(8)
      len      = len.unpack('q').shift
      response = Yajl::Parser.parse(sock.read(len))
      status   = true if response['response'] == 'success'
    rescue => e
      ## FIXME
    ensure
      disconnect
    end 

    return status
  end
end
