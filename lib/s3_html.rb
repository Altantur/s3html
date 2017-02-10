require "s3_html/version"

module S3Html
  class << self
    def hi
      puts "Hello gem world. We are gonna conquer you everyway lol."
    end
    def uploadHtml(file_path)
      extract_point = '/tmp/unzipped/'
      uniq_path = SecureRandom.uuid.to_s
      index_detected = false
      Zip::ZipFile.open(file_path) { |zip_file|
         zip_file.each { |f|
         f_path = File.join(extract_point + uniq_path, f.name)
         FileUtils.mkdir_p(File.dirname(f_path))
         zip_file.extract(f, f_path) unless File.exist?(f_path)
       }
      }
      Dir.foreach(extract_point + uniq_path) do |item|
        next if item == '.' or item == '..'
        index_detected = true if item == "index.html"
      end
      if index_detected
        uploader = S3FolderUpload.new(extract_point, uniq_path, current_account.id)
        uploader.upload!(1)
      else
        @error_message = I18n.t('push_html.invalid_page')
        return false
      end
    end
    # prefix - is directory path.
    # since s3 aws-sdk gem can't destroy whole folder we should iterate through and delete each item.
    # need return Responce for assurance of if it is deleted or not
    def delete_dir(prefix)
      Aws.config.update({
        region: S3_REGION,
        credentials: Aws::Credentials.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
      })
      s3 = Aws::S3::Resource.new(region:S3_REGION)
      obj_keys = s3.bucket(S3_BUCKET_NAME).objects(:prefix => prefix).collect(&:key)
      s3_client = get_s3_client
      obj_keys.map do |obj_key|
        s3_client.delete_object({
          bucket: S3_BUCKET_NAME,
          key: obj_key,
        })
      end
    end
    private
      def get_s3_client
          return Aws::S3::Client.new(
             credentials: Aws::Credentials.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY),
             region: S3_REGION
           )
      end


    class S3FolderUpload
      attr_reader :folder_path, :total_files, :s3_bucket
      attr_accessor :files

      def initialize(extract_point, uniq_path, account_id)
        @folder_path       = extract_point << uniq_path
        @files             = Dir.glob("#{folder_path}/**/*")
        @total_files       = files.length
        @extract_point     = extract_point
        @uniq_path         = uniq_path
        @account_id        = account_id
      end

      # public: Upload files from the folder to S3
      #
      # thread_count - How many threads you want to use (defaults to 5)
      #
      # Examples
      #   => uploader.upload!(20)
      #     true
      #   => uploader.upload!
      #     true
      #
      # When finished the process succesfully: Returns key and public_url value
      # When finished the process unsuccesfully: Returns false TODO; need some specific error return
      def upload!(thread_count = 5)
        result = nil
        file_number = 0
        mutex       = Mutex.new
        threads     = []

        thread_count.times do |i|
          threads[i] = Thread.new {
            until files.empty?
              mutex.synchronize do
                file_number += 1
                Thread.current["file_number"] = file_number
              end
              file = files.pop rescue nil
              next unless file

              path = file
              puts "[#{Thread.current["file_number"]}/#{total_files}] uploading..."
              data = File.open(file)
              if File.directory?(data)
                data.close
                next
              else
                prefix = "htmls/#{@account_id}/" << @uniq_path
                Aws.config.update({
                  region: S3_REGION,
                  credentials: Aws::Credentials.new(AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
                })
                s3 = Aws::S3::Resource.new(region:S3_REGION)
                obj = s3.bucket(S3_BUCKET_NAME).object(prefix + path.sub(@extract_point, ""))
                if obj.upload_file data, {acl: 'public-read'}
                   result = { :key_url => obj.key, :public_url => obj.public_url }
                end
                data.close
              end

            end
          }
        end
        threads.each { |t| t.join }
        final_result = {}
        if result
          final_result[:key_url] = result[:key_url].split(@uniq_path)[0] + @uniq_path
          final_result[:public_url] = result[:public_url].split(@uniq_path)[0] + @uniq_path + "/index.html"
        else
          final_result = false
        end
        return final_result
      end
    end

  end

end
