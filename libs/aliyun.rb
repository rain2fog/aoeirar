module Aliyun
  module COMMON
    def compare_snapshot(current_data,original_snapshot)
      if original_snapshot.nil?
        create_snapshot([],empty_new=1)
        original_snapshot_data=[]
      else
        File.open(original_snapshot,"r") do |fd|
          original_snapshot_data=fd.readlines
        end
      end
      original_snapshot_data.map! do |i| i.chomp! end
      create_snapshot(current_data) if (original_snapshot_data.sort != current_data.sort) || original_snapshot_data.size == 0
      increase_wave= current_data - original_snapshot_data
      decrease_wave=original_snapshot_data - current_data
      puts "increase number: #{increase_wave.size}"
      puts "decrease number: #{decrease_wave.size}"
      if increase_wave.size > 0 && decrease_wave.size == 0
        return [1,increase_wave]
      elsif increase_wave.size == 0 && decrease_wave.size > 0
        return [2,decrease_wave]
      elsif increase_wave.size > 0 && decrease_wave.size > 0
        return [3,increase_wave,decrease_wave]
      else
        return [0]
      end
    end
    
    def judgment(current_data,original_snapshot)
      wave=compare_snapshot(current_data,original_snapshot)
      puts "compare return code: #{wave.inspect}"
      if wave.size == 1
        puts "nothing change"
      else
      puts "sendmail"
      generate_email(wave)
      end
    end
  
    def send_email(subject,summary,data,recipients=ALL)
      to_recipients=String.new
      recipients.map do |i|
        to_recipients << "<"+i+">,"
      end
      to_recipients.chop!
       body=<<-EOM
<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
</head>
<body bgcolor="#FFFFFF" text="#000000">
#{summary}<br>
#{data}
</body>
</html>
EOM
  
    content=<<-EOM
From: robot@example.com
To: #{to_recipients}
Subject: #{subject}
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: 7bit

#{body}
      EOM
    
      smtp = Net::SMTP.new 'smtp.163.com', 25
      smtp.start('163.com', 'user1@163.com', 'xxxxxxxxxx', :login)
      smtp.send_message(content, 'user1@163.com', recipients)
      smtp.finish
    end
  end
  
  class ECS
    include COMMON
    TAG=self.to_s
    def get_all_ecs_info
      region = REGION
      current_data=Array.new
      region.each do |region|
#        string =`aliyuncli ecs DescribeInstances --RegionId=#{region}`
        begin
        current_data<<get_region_ecs_info(region).split("\n")
        rescue Exception => e
        next
        end
      end
      current_data.flatten
    end
    
    def get_region_ecs_info(region)
      max_pagesize=5
      json_string=`aliyuncli ecs DescribeInstances --RegionId #{region} --PageSize #{max_pagesize}`
      info=String.new
      json=JSON.parse(json_string)
      if json['TotalCount'] > max_pagesize
        pagesize = json['TotalCount']/max_pagesize.to_f == json['TotalCount']/max_pagesize ? json['TotalCount']/max_pagesize : json['TotalCount']/max_pagesize+1
        pagesize.times do |i|
          JSON.parse(`aliyuncli ecs DescribeInstances  --RegionId=#{region} --PageSize #{max_pagesize} --PageNumber #{i+1}`)['Instances']['Instance'].each do |item|
            public_ip=String.new
            if item['PublicIpAddress']['IpAddress'].class == "String"
               public_ip=item['PublicIpAddress']['IpAddress']
            else
               item['PublicIpAddress']['IpAddress'].each do |i|
                 public_ip<< "#{i} "
               end
            end
            info << "#{  item['InstanceId']};#{item['Status'].downcase!};#{item['InstanceName']};#{item['InstanceNetworkType']};#{item['InternetMaxBandwidthOut']};#{public_ip.chop!};#{item['InternetChargeType']};#{item['InstanceType'].gsub(/^ecs\./i,'')};#{item['RegionId']};#{item['CreationTime']}\n"
          end
        end
      else
        json['Instances']['Instance'].each do |item|
          public_ip=String.new
          if item['PublicIpAddress']['IpAddress'].class == "String"
             public_ip=item['PublicIpAddress']['IpAddress']
          else
             item['PublicIpAddress']['IpAddress'].each do |i|
               public_ip<< "#{i} "
             end
          end
          info << "#{  item['InstanceId']};#{item['Status'].downcase!};#{item['InstanceName']};#{item['InstanceNetworkType']};#{item['InternetMaxBandwidthOut']};#{public_ip.chop!};#{item['InternetChargeType']};#{item['InstanceType'].gsub(/^ecs\./i,'')};#{item['RegionId']};#{item['CreationTime']}\n"
        end
      end
      info
    end
    
    def generate_email(wave)
      $log.info("#{TAG} sendmail")
    # 2 or 3 arguments
    # arguments format: status increase_info decrease_info
      action=wave[0]
      code=Proc.new do |message|
        table_data='<table cellpadding="2" cellspacing="2" border="1" width="100%"><tbody><tr>
        <td valign="top">instance-id<br></td>
        <td valign="top">status<br></td>
        <td valign="top">hostname<br></td>
        <td valign="top">network_type<br></td>
        <td valign="top">max_bandwith_out<br></td>
        <td valign="top">public_ip<br></td>
        <td valign="top">internet_charge_type<br></td>
        <td valign="top">type<br></td>
        <td valign="top">region<br>
        </td><td valign="top">launch_time<br></td>'
        message.each do |record|
          table_data<<"<tr>"
          record.split(";").each do |item|
            table_data<<"<td valgn='top'>#{item}<br></td>"
          end
          table_data<<"</tr>"
        end
        table_data<<"</tbody></table>"
      end
      if action == 1
        subject="#{wave[1].size} ECS #{ wave[1].size == 1 ? "instance" : "instances"} added in Aliyun"
        summary="There were #{wave[1].size} ECS #{ wave[1].size == 1 ? "instance" : "instances"} added in your Aliyun account."
        $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
        data=code.call(wave[1])
      elsif action == 2
        subject="#{wave[1].size} ECS #{ wave[1].size == 1 ? "instance" : "instances"} removed in Aliyun"
        summary="There were #{wave[1].size} ECS #{ wave[1].size == 1 ? "instance" : "instances"} removed in your Aliyun account."
        $log.info("#{TAG} decrease number: #{wave[1].size} ; #{wave[1]}")
        data=code.call(wave[1])
      elsif action == 3
        subject="#{wave[1].size} New ECS #{ wave[1].size == 1 ? "instance" : "instances"} status changed and #{wave[2].size} Original ECS #{ wave[2].size == 1 ? "instance" : "instances"} status generated in Aliyun"
        summary="There were #{wave[1].size} new ECS #{ wave[1].size == 1 ? "instance" : "instances"} status changed in your Aliyun account."
        $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
        $log.info("#{TAG} decrease number: #{wave[2].size} ; #{wave[2]}")
        data=code.call(wave[1])+"<br>There were #{wave[2].size} old ECS #{ wave[2].size == 1 ? "instance" : "instances"} status changed in your Aliyun account<br>"+code.call(wave[2])
      end
      send_email(subject,summary,data)
    end
    
    
    def create_snapshot(current_data,empty_new=0)
      bindir=Pathname.new(File.expand_path(File.dirname(__FILE__)))
      tmpdir=bindir+"../tmp"
      puts "tmpdir: #{tmpdir}"
      if empty_new == 0
        File.open("#{tmpdir}/ecs_snapshot_#{Time.now.to_i}.csv","w") do |fd|
          current_data.each do |item|
            fd.puts item
          end  
        end
      else
        puts "#{TAG} create empty snapshot"
        $log.info("#{TAG} create empty snapshot")
        File.open("#{tmpdir}/ecs_snapshot_#{Time.now.to_i}.csv","w") 
      end
    end
    
    def fetch_snapshot
      Dir[File.expand_path(File.dirname(__FILE__))+'/../tmp/ecs_snapshot_*.csv'].sort.last
    end
  end
end
