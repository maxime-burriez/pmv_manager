require "pmv_manager/version"

require "socket"
require 'timeout'

module PmvManager

  MAX_PACKET_SIZE  = 128 # 128 octets
  RESPONSE_TIMEOUT = 1000
  PMV_DEFAULT_PORT = 10
  STX              = "\x02"
  ETX              = "\x03"
  MODES            = { automatic: "0", force: "1", off: "2" }
  STYLES           = { normal: "0", blinking: "1", bold: "2" }

  class Error               < StandardError; end
  class TimeoutError        < Error; end
  class InvalidPacketSize   < Error; end
  class InvalidMode         < Error; end
  class InvalidPageDuration < Error; end
  class InvalidMessageIndex < Error; end
  class InvalidRowIndex     < Error; end
  class InvalidPageIndex    < Error; end
  class InvalidStyle        < Error; end

  class Client
    def initialize(pmv_address, pmv_ip, pmv_port=PmvManager::PMV_DEFAULT_PORT)
      @pmv_address = pmv_address # integer
      @pmv_ip = pmv_ip           # string
      @pmv_port = pmv_port       # integer
    end
    def send(command)
      packaged_command = package(command)
      socket = UDPSocket.new
      resp = nil
      begin 
        status = Timeout::timeout(PmvManager::RESPONSE_TIMEOUT/1000) {
          socket.send packaged_command, 0, @pmv_ip, @pmv_port
          resp, _ = socket.recvfrom PmvManager::MAX_PACKET_SIZE
        }
      rescue Timeout::Error
        raise PmvManager::TimeoutError
      end
      puts resp

      resp
    end
    def xor(unpacked_command)
      unpacked_command << unpacked_command.inject(0) { |s, c| s ^ c }
    end
    def package(command)
      p = (PmvManager::STX +
        [@pmv_address.to_s(16)].pack("H*") +
        command.controle +
        PmvManager::ETX).unpack("C*")
      packaged_command = (xor p).pack("C*")
      if packaged_command.length > PmvManager::MAX_PACKET_SIZE
        raise PmvManager::InvalidPacketSize
      else
        packaged_command
      end
    end
  end

  class Command
    attr_reader :controle
    def initialize(controle)
      @controle = controle
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
