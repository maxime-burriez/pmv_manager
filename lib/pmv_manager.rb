require "pmv_manager/version"

require "socket"

module PmvManager

  MAX_PACKET_SIZE  = 128 # 128 octets
  RESPONSE_TIMEOUT = 1000
  PMV_DEFAULT_PORT = 10

  class Error < StandardError; end
  class InvalidPacketSize < Error; end

  class Client
    def initialize(pmv_address, pmv_ip, pmv_port=PmvManager::PMV_DEFAULT_PORT)
      @pmv_address = pmv_address # integer
      @pmv_ip = pmv_ip           # string
      @pmv_port = pmv_port       # integer
      # @socket = UDPSocket.new    # UDPSocket
      # @socket.connect @pmv_ip, @pmv_port
    end
    # def socket
    #   @socket
    # end
    def send(command)
      packaged_command = package(command)
      # @socket.send packaged_command, 0
      socket = UDPSocket.new
      socket.send packaged_command, 0, @pmv_ip, @pmv_port
      # resp, address = @socket.recvfrom PmvManager::MAX_PACKET_SIZE
      resp, _ = socket.recvfrom PmvManager::MAX_PACKET_SIZE
      puts resp
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
    def initialize
      super("T")
    end
  end

  class SetToForceModeCommand < WriteCommand
    def initialize
      super("B1")
    end
  end

  class InitPageCommand < WriteCommand
    def initialize
      super("F07255000000000000")
    end
  end

  class WriteMessageCommand < WriteCommand
    def initialize(message)
      super("I0007000" + message + "\x0D")
    end
  end

end
