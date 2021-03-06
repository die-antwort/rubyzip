module Zip
  class CentralDirectory
    include Enumerable

    END_OF_CENTRAL_DIRECTORY_SIGNATURE          = 0x06054b50
    MAX_END_OF_CENTRAL_DIRECTORY_STRUCTURE_SIZE = 65536 + 18
    STATIC_EOCD_SIZE                            = 22

    attr_reader :comment

    # Returns an Enumerable containing the entries.
    def entries
      @entry_set.entries
    end

    def initialize(entries = EntrySet.new, comment = "") #:nodoc:
      super()
      @entry_set = entries.kind_of?(EntrySet) ? entries : EntrySet.new(entries)
      @comment  = comment
    end

    def write_to_stream(io) #:nodoc:
      offset = io.tell
      @entry_set.each { |entry| entry.write_c_dir_entry(io) }
      write_e_o_c_d(io, offset)
    end

    def write_e_o_c_d(io, offset) #:nodoc:
      tmp = [
        END_OF_CENTRAL_DIRECTORY_SIGNATURE,
        0, # @numberOfThisDisk
        0, # @numberOfDiskWithStartOfCDir
        @entry_set ? @entry_set.size : 0,
        @entry_set ? @entry_set.size : 0,
        cdir_size,
        offset,
        @comment ? @comment.length : 0
      ]
      io << tmp.pack('VvvvvVVv')
      io << @comment
    end

    private :write_e_o_c_d

    def cdir_size #:nodoc:
                  # does not include eocd
      @entry_set.inject(0) do |value, entry|
        entry.cdir_header_size + value
      end
    end

    private :cdir_size

    def read_e_o_c_d(io) #:nodoc:
      buf                                   = get_e_o_c_d(io)
      @numberOfThisDisk                     = Entry.read_zip_short(buf)
      @numberOfDiskWithStartOfCDir          = Entry.read_zip_short(buf)
      @totalNumberOfEntriesInCDirOnThisDisk = Entry.read_zip_short(buf)
      @size                                 = Entry.read_zip_short(buf)
      @sizeInBytes                          = Entry.read_zip_long(buf)
      @cdirOffset                           = Entry.read_zip_long(buf)
      commentLength                         = Entry.read_zip_short(buf)
      if commentLength <= 0
        @comment = buf.slice!(0, buf.size)
      else
        @comment = buf.read(commentLength)
      end
      raise ZipError, "Zip consistency problem while reading eocd structure" unless buf.size == 0
    end

    def read_central_directory_entries(io) #:nodoc:
      begin
        io.seek(@cdirOffset, IO::SEEK_SET)
      rescue Errno::EINVAL
        raise ZipError, "Zip consistency problem while reading central directory entry"
      end
      @entry_set = EntrySet.new
      @size.times do
        tmp = Entry.read_c_dir_entry(io)
        @entry_set << tmp
      end
    end

    def read_from_stream(io) #:nodoc:
      read_e_o_c_d(io)
      read_central_directory_entries(io)
    end

    def get_e_o_c_d(io) #:nodoc:
      begin
        io.seek(-MAX_END_OF_CENTRAL_DIRECTORY_STRUCTURE_SIZE, IO::SEEK_END)
      rescue Errno::EINVAL
        io.seek(0, IO::SEEK_SET)
      end
      buf      = io.read
      sigIndex = buf.rindex([END_OF_CENTRAL_DIRECTORY_SIGNATURE].pack('V'))
      raise ZipError, "Zip end of central directory signature not found" unless sigIndex
      buf = buf.slice!((sigIndex + 4)..(buf.bytesize))

      def buf.read(count)
        slice!(0, count)
      end

      buf
    end

    # For iterating over the entries.
    def each(&proc)
      @entry_set.each(&proc)
    end

    # Returns the number of entries in the central directory (and 
    # consequently in the zip archive).
    def size
      @entry_set.size
    end

    def CentralDirectory.read_from_stream(io) #:nodoc:
      cdir = new
      cdir.read_from_stream(io)
      return cdir
    rescue ZipError
      return nil
    end

    def ==(other) #:nodoc:
      return false unless other.kind_of?(CentralDirectory)
      @entry_set.entries.sort == other.entries.sort && comment == other.comment
    end
  end
end

# Copyright (C) 2002, 2003 Thomas Sondergaard
# rubyzip is free software; you can redistribute it and/or
# modify it under the terms of the ruby license.
