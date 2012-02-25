require "nokogiri"
require "data_mapper"

module Clasrip
  class SQL
    class Classification
      include DataMapper::Resource

      property :id, Serial
      property :title, Text
      property :original_url, Text
      property :classification, Text
      property :consumer_advice, Text
      property :category, Text
      property :medium, Text
      property :version, Text
      property :duration, Text
      property :date_of_classification, Date
      property :author, Text
      property :publisher, Text
      property :production_company, Text
      property :country_of_origin, Text
      property :applicant, Text
      property :file_number, Text
      property :classification_number, Text

      self.raise_on_save_failure = true
    end
    
    class PEGIRating
      include DataMapper::Resource

      property :id, Serial
      property :title, Text
      property :release_date, Date
      property :url, Text
      property :platform, Text
      property :base_age_category, Text
      property :violence, Boolean
      property :sex, Boolean
      property :drugs, Boolean
      property :fear, Boolean
      property :discrimination, Boolean
      property :bad_language, Boolean
      property :gambling, Boolean
      property :pegi_online, Boolean

      self.raise_on_save_failure = true
    end

    def initialize(sql_url)
      sql_url = sql_url.sub("///", "//#{Dir.pwd}/")
      #DataMapper::Logger.new($stdout, :debug)
      DataMapper.setup(:default, sql_url)
      Classification.auto_upgrade!
      PEGIRating.auto_upgrade!
    end

    def add_record(record, type=:classification)
      if type == :classification
        Classification.create(record)
      elsif type == :pegi
        PEGIRating.create(record)
      else
        raise "type not supported"
      end
    end

    def parse_xml(xml_fn)
      print "Parsing XML... "
      xml = Nokogiri::XML(xml_fn, &:noblanks)
      puts "Done."

      classifications = xml.css("classifications > classification")
      count = 0
      record = Classification.last
      puts "Null record" if record == nil
      wait = (record == nil) ? false : true
      
      puts "Record: #{record.attributes[:title]}" unless record == nil
      print "Finding position... " unless record == nil
      classifications = classifications.drop_while do |i|
        if wait == true
          res = record.attributes[:classification_number] == i.at_css("classification-number").content
          wait = false if res == true
          if wait == false
            puts "Done!"
            return true
          end
        end
        wait
      end
      clen = classifications.length

      classifications.each do |node|
        count += 1
        c = {}
        node.children.each do |child|
          next if child.name == "text"
          name = child.name.gsub("-", "_").to_sym
          if name == :date_of_classification
            date = Date.strptime(child.content, "%Y-%m-%d")
            c[name] = date
          else
            c[name] = child.content
          end
        end
        cls = Classification.create(c)
        print "\r#{count}/#{clen}"
      end
      puts "\nDone!"
    end

    def to_xml(table)
      #stub
    end
  end
end

DataMapper.finalize
