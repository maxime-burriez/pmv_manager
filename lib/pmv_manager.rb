require "pmv_manager/version"

require "socket"

module PmvManager

  MAX_PACKET_SIZE  = 128 # 128 octets
  RESPONSE_TIMEOUT = 1000
  PMV_DEFAULT_PORT = 10

  class InvalidPacketSize < StandardError; end

  class Client
    def initialize(pmv_address, pmv_ip, pmv_port=PmvManager::PMV_DEFAULT_PORT)
      @pmv_address = pmv_address # integer
      @pmv_ip = pmv_ip           # string
      @pmv_port = pmv_port       # integer
      # @socket = UDPSocket.new    # UDPSocket
    end
    # def socket
    #   @socket
    # end
    def send(command)
      packaged_command = package(command)
      socket = UDPSocket.new
      socket.send packaged_command, 0, @ip, @pmv_port
      socket.recv PmvManager::MAX_PACKET_SIZE
    end
    def package(command)
      p = ("\x02#{[@pmv_address.to_s(16)].pack("H*")}#{command.definition}\x03").unpack("C*")
      packaged_command = (p << p.inject(0) { |s, c| s ^ c }).pack("C*")
      if packaged_command.length > PmvManager::MAX_PACKET_SIZE
        raise PmvManager::InvalidPacketSize
      else
        packaged_command
      end
    end
  end

  class Command
    def initialize(definition)
      @definition = definition
    end
    def definition
      @definition
    end
  end

  class WriteCommand < Command
    def initialize(definition)
      super(definition)
      @definition = "W" + @definition
    end
  end

  class TestCommand < WriteCommand
    def initialize()
      super("T")
    end
  end

end
