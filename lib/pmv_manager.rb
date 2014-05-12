require "pmv_manager/version"

require "socket"
require 'timeout'

module PmvManager

  PMV_DEFAULT_PORT = 10
  MAX_PACKET_SIZE  = 128 # 128 octets
  RESPONSE_TIMEOUT = 2000
  NAK              = "\x15\x15\x15\x15\x15" # false
  ACK              = "\x06\x06\x06\x06\x06" # true
  STX              = "\x02"
  ETX              = "\x03"
  MODES            = { automatic: "0", force: "1", off: "2" }
  STYLES           = { normal: "0", blinking: "1", bold: "2" }

  class Error               < StandardError; end
  class TimeoutError        < Error; end
  class NetworkError        < Error; end
  class InvalidPacketSize   < Error; end
  class InvalidMode         < Error; end
  class InvalidPageDuration < Error; end
  class InvalidMessageIndex < Error; end
  class InvalidRowIndex     < Error; end
  class InvalidPageIndex    < Error; end
  class InvalidStyle        < Error; end

  class Client
    attr_reader :pmv_address, :pmv_ip, :pmv_port
    def initialize(pmv_address, pmv_ip, pmv_port=PmvManager::PMV_DEFAULT_PORT)
      @pmv_address = pmv_address # integer
      @pmv_ip = pmv_ip           # string
      @pmv_port = pmv_port       # integer
    end
    def send(command)
      command.send(self)
    end
  end

  class Command
    attr_reader :controle
    def initialize(controle)
      @controle = controle
    end
    def send(client)
      packaged_command = package(client.pmv_address)
      socket = UDPSocket.new
      resp = nil
      begin
        Timeout::timeout(PmvManager::RESPONSE_TIMEOUT/1000) {
          socket.send packaged_command, 0, client.pmv_ip, client.pmv_port
          resp, _ = socket.recvfrom PmvManager::MAX_PACKET_SIZE
        }
      rescue Timeout::Error
        raise PmvManager::TimeoutError
      rescue Errno::ENETUNREACH
        raise PmvManager::NetworkError
      end
      json_resp = resp_to_json(resp)
      socket.close
      puts json_resp
      json_resp
    end
    def xor(unpacked_command)
      unpacked_command << unpacked_command.inject(0) { |s, c| s ^ c }
    end
    def package(pmv_address)
      p = (PmvManager::STX +
        [pmv_address.to_s(16)].pack("H*") +
        @controle +
        PmvManager::ETX).unpack("C*")
      packaged_command = (xor p).pack("C*")
      if packaged_command.length > PmvManager::MAX_PACKET_SIZE
        raise PmvManager::InvalidPacketSize
      else
        packaged_command
      end
    end
    def resp_to_json(resp)
      case resp
      when PmvManager::NAK
        { status: false }
      when PmvManager::ACK
        { status: true }
      end
    end
  end

  class ReadCommand < Command
    def initialize(controle)
      super("R" + controle)
    end
  end

  class GetModeCommand < ReadCommand
    def initialize
      super("B")
    end
    def resp_to_json(resp)
      mode = PmvManager::MODES.key ([resp.unpack("C*")[4]].pack("C*"))
      { mode: mode }
    end
  end

  class GetRowsNumberCommand < ReadCommand
    def initialize
      super("C")
    end
    def resp_to_json(resp)
      unpacked_resp = resp.unpack("C*")
      n = unpacked_resp[4..(unpacked_resp.length-3)].pack("C*").to_i
      { rows_number: n }
    end
  end

  class GetMessageCommand < ReadCommand
    def initialize options
      controle = "I"
      if (0..9).to_a.include? options[:row_index]
        controle += options[:row_index].to_s.rjust(2, "0")
      else
        raise PmvManager::InvalidRowIndex
      end
      if (0..8).to_a.include? options[:message_index]
        controle += options[:message_index].to_s.rjust(2, "0")
      else
        raise PmvManager::InvalidMessageIndex
      end
      if (0..4).to_a.include? options[:page_index]
        controle += options[:page_index].to_s.rjust(2, "0")
      else
        raise PmvManager::InvalidPageIndex
      end
      super(controle)
    end
    def resp_to_json(resp)
      style = PmvManager::STYLES.key ([resp.unpack("C*")[4]].pack("C*"))
      unpacked_resp = resp.unpack("C*")
      msg = unpacked_resp[5..(unpacked_resp.length-4)].pack("C*")
      { style: style, message: msg }
    end
  end

  class WriteCommand < Command
    def initialize(controle)
      super("W" + controle)
    end
  end

  class TestCommand < WriteCommand
    def initialize
      super("T")
    end
  end

  class SwitchToModeCommand < WriteCommand
    def initialize options
      controle = "B"
      if PmvManager::MODES.include? options[:mode]
        controle += PmvManager::MODES[options[:mode]]
      else
        raise PmvManager::InvalidMode
      end
      super(controle)
    end
  end

  class InitPageCommand < WriteCommand
    def initialize options
      controle = "F"
      if (0..7).to_a.include? options[:message_index]
        controle += options[:message_index].to_s.rjust(2, "0")
      else
        raise PmvManager::InvalidMessageIndex
      end
      add_page_duration controle, options[:page_duration_1]
      add_page_duration controle, options[:page_duration_2]
      add_page_duration controle, options[:page_duration_3]
      add_page_duration controle, options[:page_duration_4]
      add_page_duration controle, options[:page_duration_5]
      super(controle)
    end

    private

    def add_page_duration controle, page_duration
      if ((0..180).to_a << 255).include? page_duration
        controle += page_duration.to_s.rjust(3, "0")
      else
        raise PmvManager::InvalidPageDuration
      end
    end
  end

  class WriteMessageCommand < WriteCommand
    def initialize options
      controle = "I"
      if (0..9).to_a.include? options[:row_index]
        controle += options[:row_index].to_s.rjust(2, "0")
      else
        raise PmvManager::InvalidRowIndex
      end
      if (0..7).to_a.include? options[:message_index]
        controle += options[:message_index].to_s.rjust(2, "0")
      else
        raise PmvManager::InvalidMessageIndex
      end
      if (0..4).to_a.include? options[:page_index]
        controle += options[:page_index].to_s.rjust(2, "0")
      else
        raise PmvManager::InvalidPageIndex
      end
      if PmvManager::STYLES.include? options[:style]
        controle += PmvManager::STYLES[options[:style]]
      else
        raise PmvManager::InvalidStyle
      end
      controle += options[:message] + "\x0D"
      super(controle)
    end
  end

end
