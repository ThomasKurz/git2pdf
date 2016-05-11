#require 'bundler/setup'
require 'open-uri'
require 'json'

class Git2Pdf
  attr_accessor :repos
  attr_accessor :basic_auth

  def initialize(options={})
    @repos = options[:repos] || []
    @basic_auth = options[:basic_auth] || nil
    @org = options[:org] || nil
    @issue_titles = Hash.new ""
    @labels = "&labels=#{options[:labels]}" || ''
  end

  def get_issues(repo)
      json = ""
      if @org
        json = open("https://api.github.com/repos/#{@org}/#{repo}/issues?per_page=200&state=open#{@labels}", :http_basic_authentication => basic_auth).read
      else
        # for stuff like bob/stuff
        json = open("https://api.github.com/repos/#{repo}/issues?per_page=200&state=open#{@labels}", :http_basic_authentication => basic_auth).read
      end
      JSON.parse(json)
  end

  def execute
    batch = generate_postits
    pdf(batch)
  end

  def generate_postits
    batch = []

    self.repos.each do |repo|
      issues = get_issues repo
      issues.each do |val|
        @issue_titles[val["number"].to_s] = val["title"]
        users = []
        user_story = ""
        val["body"] && val["body"].split("\n").each do |line|
            user = /@(.{7}).+:\s(.+)h/.match line
            users << user.captures unless user == nil
            story = /User Story: #(.+)/.match(line)
            user_story = story.captures[0] unless story == nil
        end

        labels = val["labels"].collect { |l| l["name"].upcase }.join(', ')
        type = ""
        type = "BUG" if labels =~ /bug/i #not billable
        type = "FEATURE" if labels =~ /feature/i #billable
        type = "ENHANCEMENT" if labels =~ /enhancement/i #billable
        type = "AMEND" if labels =~ /amend/i #not billable
        type = "TASK" if labels =~ /task/i #not billable

        time = ""
        time = "1 day" if labels =~ /1d/i
        time = "2 days" if labels =~ /2d/i
        time = "5 days" if labels =~ /5d/i
        time = "10 days" if labels =~ /10d/i
        time = "4 weeks" if labels =~ /4w/i
        time = "half day" if labels =~ /halfday/i

        kanban = "backlog"
        kanban = "backlog" if labels =~ /backlog/i
        kanban = "ready" if labels =~ /ready/i
        kanban = "in progress" if labels =~ /in progress/i
        kanban = "done" if labels =~ /done/i

        milestone = val["milestone"] ? val["milestone"]["title"] : ""
        assignee = val["assignee"] ? val["assignee"]["login"] : ""

        #labels.include?(['BUG','FEATURE','ENHANCEMENT','QUESTION'])
        hash = {short_title: repo, ref: "#{val["number"]}", long_title: "#{val["title"]}", type: type, kanban: kanban, time: time, due: "", labels: labels, milestone: "#{milestone}", assignee: "#{assignee}", users: users, user_story: user_story}
        batch << hash unless labels.split(",") == ["STORY"]
      end
    end
    batch
  end

  def pdf(batch)
    require 'prawn'
    issue_titles = @issue_titles
    row = 0
    col = 0
    margin = 20
    Prawn::Document.generate("issues.pdf", :page_size => "A7", :margin => 0, :page_layout => :landscape) do
      dir = File.expand_path File.dirname(__FILE__)
      font_families.update(
          "Lato" => {:bold => "#{dir}/assets/fonts/Lato-Bold.ttf",
                     :italic => "#{dir}/assets/fonts/Lato-LightItalic.ttf",
                     :bold_italic => "#{dir}/assets/fonts/Lato-BoldItalic.ttf",
                     :normal => "#{dir}/assets/fonts/Lato-Regular.ttf",
                     :light => "#{dir}/assets/fonts/Lato-Light.ttf"})
      font 'Lato'
      batch = batch.sort { |a, b| a["ref"]<=>b["ref"] and a["project"]<=>b["project"] }
      logo = open("http://www.pocketworks.co.uk/images/logo.png")
      #logo = open("#{dir}/assets/images/pocketworks.png")
      fill_color(0,0,0,100)
      batch.each do |issue|

        y_offset = 205

        #Ref
        font 'Lato', :style => :bold, size: 24
        text_box "##{issue[:ref]}" || "", :at => [185, y_offset], :width => 100, :overflow => :shrink_to_fit, :align => :right
        #
        #Short title
        short_title = issue[:short_title]
        short_title = short_title.split('/')[1] if short_title =~ /\//
        font 'Lato', :style => :light, size: 10
        text_box "Repo: " + short_title, :at => [margin, y_offset], :width => 210-margin, :overflow => :shrink_to_fit

        if issue[:milestone] and issue[:milestone] != ""
          y_offset = y_offset - 20
          # Milestone
          font 'Lato', :style => :light, size: 12
          text_box "Milestone: " + issue[:milestone].upcase, :at => [margin, y_offset], :width => 280, :overflow => :shrink_to_fit
          #text_box fields["due"] || "", :at=>[120,20], :width=>60, :overflow=>:shrink_to_fit
          y_offset = y_offset + 20
        end

        fill_color "EEEEEE"
        fill_color "D0021B" if issue[:type] == "BUG"
        fill_color "1D8FCE" if issue[:type] == "TASK"
        fill_color "FBF937" if issue[:type] == "FEATURE"
        fill_color "F5B383" if issue[:type] == "AMEND"
        fill_color "FBF937" if issue[:type] == "ENHANCEMENT"

        if issue[:type] and issue[:type] != ""
          fill{rectangle([0,220], margin-10, 220)}
        else
          fill{rectangle([0,220], margin-10, 220)}
        end

        fill_color(0,0,0,100)

        if issue[:long_title]
          y_offset = y_offset - 60
          # Long title
          font 'Lato', :style => :bold, size: 14
          text_box issue[:long_title] ? issue[:long_title][0..100] : "NO DESCRIPTION", :at => [margin, y_offset], :width => 280-margin, :overflow => :shrink_to_fit
        end

        if issue[:users].size > 0 then
            font 'Lato', :style => :normal, size: 10
            start_users = 25
            end_users = 50 * issue[:users].size() + start_users
            horizontal_line start_users, end_users, :at => 120
            horizontal_line start_users, end_users, :at => 130
            horizontal_line start_users, end_users, :at => 25
            vertical_line 130, 25, :at => end_users
            stroke
            issue[:users].each do |x|
                text_box x[0], :at => [start_users + 3, 130], :width => 210-margin, :overflow => :shrink_to_fit
                text_box x[1], :at => [start_users + 3, 120 - 2], :width => 210-margin, :overflow => :shrink_to_fit
                vertical_line 130, 25, :at => start_users
                vertical_line 120, 25, :at => start_users + 25
                stroke
                start_users += 50
            end
        end

        # kanban state
        font 'Lato', :style => :italic, size: 8
        text_box issue[:kanban].length == 0 ? "" : "Kanban state: " + issue[:kanban],
          :at => [margin, 90+margin],
          :width => 220-margin,
          :overflow =>
          :shrink_to_fit,
          :align => :left

        # estimated time
        font 'Lato', :style => :italic, size: 8
        text_box issue[:time].length == 0 ? "Est. time: ???" : "Est. time: " + issue[:time],
          :at => [margin, 80+margin],
          :width => 220-margin,
          :overflow =>
          :shrink_to_fit,
          :align => :left

        # assignee
        font 'Lato', :style => :bold, size: 8
        text_box issue[:assignee].length == 0 ? "Responsible:\r\n???" : "Responsible:\r\n" + issue[:assignee],
          :at => [220, 70+margin],
          :width => 70-margin,
          :height => 70,
          :overflow => :shrink_to_fit,
          :align => :right,
          :valign => :bottom

          # Labels
        font 'Lato', :style => :normal, size: 8
        lb = issue[:labels].gsub(",", "\r\n")
        text_box issue[:labels].length == 0 ? "" : lb,
          :at => [margin, 70+margin],
          :width => 150-margin,
          :height => 70,
          :overflow => :shrink_to_fit,
          :align => :left,
          :valign => :bottom

        #end

        start_new_page unless issue == batch[batch.length-1]
      end
    end
    batch.length
  end
end
