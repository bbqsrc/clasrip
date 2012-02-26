require "nokogiri"
require "net/http"

module Clasrip
  module Version
    MAJOR = 0
    MINOR = 1
    PATCH = 1
    BUILD = nil
    def self.to_s
      [MAJOR, MINOR, PATCH, BUILD].compact.join('.')
    end
  end

  class DataIntegrityWarning < Exception; end
  
  class DatesBetween
    attr_accessor :year, :month, :day

    def initialize(start, finish)
      @day = 0
      @year = start
      @finish = finish
      @month = 0
    end

    def to_s
      "#{@day}/#{@month}/#{@year}"
    end

    def next
      raise StopIteration if @year >= @finish
      if @day >= 1 and @day < 15
        @day = 15
      else 
        @month += 1
        @day = 1
      end
      
      if @month > 12
        @month = 1
        @year += 1
      end
      
      to_s 
    end

    def each
      loop do
        yield self.next
      end
    rescue StopIteration
      self
    end
  end

  class Scraper
    def initialize(start_year, end_year)
      @dates = [
        DatesBetween.new(start_year, end_year), 
        DatesBetween.new(start_year, end_year)
      ]
      @dates[1].next

      @host_url = "www.classification.gov.au"
      @query_url = "/www/cob/find.nsf/classifications?search&searchwv=1&searchmax=1000&count=1000&query=(%%5BclassificationDate%%5D%%3E=%s)AND(%%5BclassificationDate%%5D%%3C%s)"
      new_conn
      new_enum
    end
    
    def next
      @records.next
    end

    def each
      @records.each do |r|
        yield r
      end
    end

    def peek
      @records.peek
    end

    def set_date(year, month, day)
      @dates.each do |date|
        date.year = year.to_i
        date.month = month.to_i
        date.day = day.to_i
      end
      @dates[1].next
    end

    def get_date
      @dates[0]
    end

    private
    def new_conn
      @conn = Net::HTTP.new(@host_url, 80)
      @conn.read_timeout = 3
      @conn.start
    end

    def get_conn(arg)
      begin
        return @conn.get(arg)
      rescue
        new_conn
        retry
      end
    end
    
    def ensure_correct_encoding(s)
      s.force_encoding("utf-8")
      return s if s.valid_encoding?

      puts ("Invalid: " + s)
      s.encode!("utf-8", "iso-8859-1")
      raise "Could not enforce UTF-8 encoding: '#{s}'" unless s.valid_encoding?
      s
    end

    def new_enum
      @records = Enumerator.new do |y|
        @dates[0].each do |first_date|
          second_date = @dates[1].next
       
          tables = []
          begin
            t = get_table or next 
            check_result_count
            tables.push(t)
          rescue DataIntegrityWarning
            tables_by_rating do |table|
              next if table == nil
              check_result_count
              tables.push(table)
            end
          end
      
          tables.each do |table|
            parse_table(table).each do |record|
              form = get_classification(record[:original_url]) or next
              record.merge!(parse_classification(form))
              record.each_pair do |k,v|
                record[k] = ensure_correct_encoding(v)
              end
              y << record
            end
          end
        end
      end
    end
    
    def tables_by_rating
	    ratings = {
				"Unrestricted" => ["Unrestricted"],
				"G" => ["Likely G", "G"],
				"PG" => ["Likely PG", "PG", "G 8+"],
				"M" => ["Likely M", "M"],
				"MA" => ["Likely MA 15+", "MA15+ Conditions", "MA 15+"],
				"R" => ["Likely R 18+", "R", "R 18+"],
				"X" => ["Likely X 18+", "X", "X 18+"],
				"CAT1" => ["CAT 1"],
				"CAT2" => ["CAT 2"],
				"RC" => ["RC"],
				"Misc" => ["Revoked", "Ad Approved", "Approved", "Ad Refused", "Refused"]
	    }
	
	    ratings.each_pair do |k,v|
        q = v.map{|i| "(%5Brating=#{i.gsub(' ', '+')}%5D)"}
        x = "AND(#{q.join('OR')})"
        res = get_conn(@query_url % [@dates[0].to_s, @dates[1].to_s] + x)
        @html = Nokogiri::HTML(res.read_body)
        yield @html.at_css("#results > table")
      end
    end

    def check_result_count
      results = @html.at_css(".content p").content
      results = results.sub(/.*of (\d+) .*/, "\\1").to_i
      if results == 1000
        raise DataIntegrityWarning, "1000 results detected. Some records may be missed for URL: #{@query_url % [@dates[0].to_s, @dates[1].to_s]}"
      end
      results
    end

    def get_table
      res = get_conn(@query_url % [@dates[0].to_s, @dates[1].to_s])
      @html = Nokogiri::HTML(res.read_body)
      return @html.at_css("#results > table") 
    end
    
    def parse_table(table)
      records = []
      table.xpath("tr").each do |row|
        row.children[0].node_name == "td" or next
        record = {}
        
        record[:title] = row.xpath('td[2]/a').first.content
        record[:original_url] = row.xpath('td[2]/a').first['href'].split('/').last.split('?').first
        
        records.push(record)
      end
      return records
    end
    
    def get_classification(url)
      res = get_conn("/www/cob/find.nsf/d853f429dd038ae1ca25759b0003557c/#{url}")
      @html = Nokogiri::HTML(res.read_body)
      @html.at_css(".fform")
    end

    def parse_classification(form)
      record = {}
      form.css(".frow").each do |row|
        label = row.at_css(".flabel").content.strip.downcase.gsub(" ", "_").to_sym
        field = row.at_css(".ffield").content
        
        field = field.encode("UTF-8") unless field.valid_encoding?
        field = field.strip.gsub("\u00A0", "") if field.valid_encoding?

        if label == :date_of_classification
          date = field.split('/')
          field = "#{date[2]}-#{date[0]}-#{date[1]}"
        elsif label == :version
          fld = @html.at_css(".content p").children[1]
          record[:medium] = fld.content.sub(/.*\((.*?)\)/, "\\1") if fld != nil
          record[:medium] = "" if fld == nil
        end
        
        record[label] = field
      end
      record
    end
  end
end
