# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008-2009 TIS Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'jcode'
require 'open-uri'
require "resolv-replace"
require 'timeout'
require 'rss'
class MypageController < ApplicationController
  before_filter :setup_layout
  before_filter :load_user
  skip_before_filter :verify_authenticity_token, :only => :apply_ident_url

  verify :method => :post, :only => [ :destroy_portrait, :save_portrait, :update_profile,
                                      :update_message_unsubscribes, :apply_password,
                                      :add_antenna, :delete_antenna, :delete_antenna_item, :move_antenna_item,
                                      :change_read_state, :apply_email, :set_antenna_name, :sort_antenna],
         :redirect_to => { :action => :index }
  verify :method => [:post, :put], :only => [ :update_customize], :redirect_to => { :action => :index }

  # ================================================================================
  #  tab menu actions
  # ================================================================================

  # mypage > home
  def index
    # ============================================================
    #  right side area
    # ============================================================
    @year, @month, @day = parse_date
    @entry_count_hash = get_entry_count(@year, @month)
    @recent_groups =  Group.active.recent(recent_day).order_recent.limit(5).all
    @recent_users = User.recent(recent_day).order_recent.limit(5).all

    # ============================================================
    #  main area top messages
    # ============================================================
    current_user_info = current_user.info
    @system_messages = system_messages
    @message_array = Message.get_message_array_by_user_id(current_user.id)
    @waiting_groups = Group.find_waitings(current_user.id)
    # あなたへの連絡（公開・未読/既読は関係なし・最近のもののみ）
    @important_your_messages = important_your_messages
    # あなたへの連絡（非公開・未読のもののみ）
    @mail_your_messages = mail_your_messages

    # ============================================================
    #  main area entries
    # ============================================================
    @questions = find_questions_as_locals({:recent_day => recent_day, :per_page => 5})
    @access_blogs = find_access_blogs_as_locals({:per_page => 8})
    @recent_blogs = find_recent_blogs_as_locals({:per_page => 8})
    @recent_bbs = recent_bbs

    # ============================================================
    #  main area bookmarks
    # ============================================================
    @bookmarks = Bookmark.find_visible(5, recent_day)
  end

  # mypage > profile
  def profile
    flash.keep(:notice)
    redirect_to get_url_hash('show')
  end

  # mypage > blog
  def blog
    redirect_to get_url_hash('blog', :archive => 'all', :sort_type => 'date')
  end

  # mypage > file
  def share_file
    redirect_to get_url_hash('share_file')
  end

  # mypage > social
  def social
    redirect_to get_url_hash('social')
  end

  # mypage > group
  def group
    redirect_to get_url_hash('group')
  end

  # mypage > bookmark
  def bookmark
    redirect_to get_url_hash('bookmark')
  end

  # mypage > trace(足跡)
  def trace
    @access_count = current_user.user_access.access_count
    @access_tracks = current_user.tracks
  end

  # mypage > manage(管理)
  def manage
    @title = _("Self Admin")
    @user = current_user
    @menu = params[:menu] || "manage_profile"
    case @menu
    when "manage_profile"
      @profiles = current_user.user_profile_values
    when "manage_password"
      redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:password)
    when "manage_email"
      @applied_email = AppliedEmail.find_by_user_id(session[:user_id]) || AppliedEmail.new
    when "manage_openid"
      redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:free_rp)
      @openid_identifier = @user.openid_identifiers.first || OpenidIdentifier.new
    when "manage_portrait"
      @picture = current_user.picture || current_user.build_picture
      render :template => 'pictures/new', :layout => 'layout' and return
    when "manage_customize"
      @user_custom = UserCustom.find_by_user_id(@user.id) || UserCustom.new
    when "manage_antenna"
      @antennas = find_antennas
    when "manage_message"
      @unsubscribes = UserMessageUnsubscribe.get_unscribe_array(session[:user_id])
    # TODO #924で画面からリンクをなくした。1.4時点で復活しない場合は削除する
    when "record_mail"
      set_data_for_record_mail
    when "record_post"
      set_data_for_record_blog
    else
      render_404 and return
    end
    render :partial => @menu, :layout => "layout"
  end

  # ================================================================================
  #  mypage > home 関連
  # ================================================================================

  # 公開されている記事一覧画面を表示
  def entries
    unless params[:list_type]
      redirect_to :controller => 'search', :action => 'entry_search' and return
    end
    unless valid_list_types.include?(params[:list_type])
      render_404 and return
    end
    locals = find_as_locals(params[:list_type], {:per_page => 20})
    @id_name = locals[:id_name]
    @title_icon = locals[:title_icon]
    @title_name = locals[:title_name]
    @entries = locals[:pages]
    @symbol2name_hash = locals[:symbol2name_hash]
  end

  # 指定日の投稿記事一覧画面を表示
  def entries_by_date
    year, month, day = parse_date
    @selected_day = Date.new(year, month, day)
    @entries = find_entries_at_specified_date(@selected_day)
    @next_day = first_entry_day_after_specified_date(@selected_day)
    @prev_day = last_entry_day_before_specified_date(@selected_day)
  end

  # アンテナ毎の記事一覧画面を表示
  def entries_by_antenna
    @antenna_entry = antenna_entry(params[:antenna_id], params[:read])
    @antenna_entry.title = antenna_entry_title(@antenna_entry)
    if @antenna_entry.need_search?
      find_params = @antenna_entry.conditions
      @entries = BoardEntry.scoped(
        :conditions=> find_params[:conditions],
        :include => find_params[:include] | [ :user, :state ]
      ).order_new.paginate(:page => params[:page], :per_page => 20)
      @user_unreadings = unread_entry_id_hash_with_user_reading(@entries.map {|entry| entry.id})
      @symbol2name_hash = BoardEntry.get_symbol2name_hash(@entries)
    end
  end

  # ajax_action
  # 未読・既読を変更する
  def change_read_state
    ur = UserReading.create_or_update(session[:user_id], params[:board_entry_id], params[:read])
    render :text => ur.read? ? _('Entry was successfully marked read.') : _('Entry was successfully marked unread.')
  end

  # ajax action
  # 指定月のカレンダに切り替える
  def load_calendar
    # parse出来ないケースで例外を起こして現在時刻を設定するため
    date = Time.parse("#{params[:year]}/#{params[:month]}", 0) rescue Time.now
    render :partial => "shared/calendar",
           :locals => { :sel_year => date.year,
                        :sel_month => date.month,
                        :sel_day => nil,
                        :item_count => get_entry_count(params[:year], params[:month]),
                        :action => 'entries_by_date'}
  end

  # ajax_action
  # [公開された記事]のページ切り替えを行う。
  # param[:target]で指定した内容をページ単位表示する
  def load_entries
    option = { :per_page => params[:per_page].to_i }
    option[:recent_day] = params[:recent_day].to_i if params[:recent_day]
    render :partial => (params[:page_name] ||= "page_space"), :locals => find_as_locals(params[:target], option)
  end

  # ajax_action
  # 右側サイドバーのRSSフィードを読み込む
  def load_rss_feed
    feeds = []
    Admin::Setting.mypage_feed_settings.each do |setting|
      feed = nil
      timeout(Admin::Setting.mypage_feed_timeout.to_i) do
        feed = open(setting[:url], :proxy => SkipEmbedded::InitialSettings['proxy_url']){ |f| RSS::Parser.parse(f.read) }
      end
      feed = unify_feed_form(feed, setting[:title], setting[:limit])
      feeds << feed if feed
    end
    render :partial => "rss_feed", :locals => { :feeds => feeds }
  rescue Timeout::Error
    render :text => _("Timeout while loading rss.")
    return false
  rescue Exception => e
    logger.error e
    e.backtrace.each { |line| logger.error line}
    render :text => _("Failed to load rss.")
    return false
  end

  # ================================================================================
  #  アンテナの整備関連
  # ================================================================================

  def set_antenna_name
    id = params[:element_id] ? params[:element_id].split('_')[3] : nil

    antenna = Antenna.find(id)
    unless antenna.user_id == session[:user_id]
      render :text => ""
      return false
    end
    antenna.name = params[:value]
    if antenna.save
      # Inplaceエディタ内で直接ここで返した文字列を表示するためにHTMLエスケープする
      render :text => ERB::Util.html_escape(antenna.name)
    else
      render :text => antenna.errors.full_messages.first, :status => 500
    end
  end

  def add_antenna
    Antenna.create(:user_id => session[:user_id], :name => params[:antenna_name])
    render :partial => 'antennas', :object => find_antennas
  end

  def delete_antenna
    antenna = Antenna.find(params[:antenna_id])
    unless antenna.user_id == session[:user_id]
      render :text => ""
      return false
    end
    antenna.destroy
    render :partial => 'antennas', :object => find_antennas
  end

  def delete_antenna_item
    item = AntennaItem.find(params[:antenna_item_id])
    unless item.antenna.user_id == session[:user_id]
      render :text => ""
      return false
    end
    item.destroy
    render :partial => 'antennas', :object => find_antennas
  end

  def move_antenna_item
    antenna_item = AntennaItem.find(params[:antenna_item_id])
    antenna_item.antenna_id = params[:antenna_id]
    if antenna_item.save
      render :partial => 'antennas', :object => find_antennas
    else
      render :text => antenna_item.errors.full_messages, :status => :bad_request
    end
  end

  def sort_antenna
    antennas = Antenna.find(:all,
                            :conditions => ["user_id = ?", session[:user_id]],
                            :order => "position")
    target_pos = Integer(params[:target_pos])

    antennas.each_with_index do |antenna, index|
      if antenna.id.to_s == params[:source_antenna_id]
        if target_pos > antenna.position
          antennas.insert(target_pos, antenna)
          antennas.delete_at(index)
        else
          antennas.delete_at(index)
          antennas.insert(target_pos-1, antenna)
        end
        break
      end
    end
    antennas.each_with_index do |antenna, index|
      if antenna && (antenna.position != (index + 1))
        antenna.position = index + 1;
        antenna.save
      end
    end
    render :partial => 'antennas', :object => find_antennas
  end

  def antenna_list
    render :text => current_user_antennas_as_json
  end

  # ================================================================================
  #  mypage > manage(管理) 関連
  # ================================================================================

  # post_action
  def update_profile
    @user = current_user
    @user.attributes = params[:user]
    @profiles = @user.find_or_initialize_profiles(params[:profile_value])

    User.transaction do
      @user.save!
      @profiles.each{|profile| profile.save!}
    end
    flash[:notice] = _('User information was successfully updated.')
    redirect_to :action => 'profile'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    @error_msg = []
    @error_msg.concat @user.errors.full_messages unless @user.valid?
    @error_msg.concat SkipUtil.full_error_messages(@profiles)

    render :partial => 'manage_profile', :layout => "layout"
  end

  # post_action
  # メール通知設定
  # 画面表示とテーブルレコードが逆なので注意
  # Message::MESSAGE_TYPESにあるけど、params["message_type"]にないときにcreate
  def update_message_unsubscribes
    UserMessageUnsubscribe.delete_all(["user_id = ?", session[:user_id]])
    Message::MESSAGE_TYPES.keys.each do |message_type|
      unless  params["message_type"] && params["message_type"][message_type]
        UserMessageUnsubscribe.create(:user_id => session[:user_id], :message_type => message_type )
      end
    end
    flash[:notice] = _('Updated notification email settings.')
    redirect_to :action => 'manage', :menu => 'manage_message'
  end

  def apply_password
    redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:password)

    @user = current_user
    @user.change_password(params[:user])
    if @user.errors.empty?
      flash[:notice] = _('Password was successfully updated.')
      redirect_to :action => :manage, :menu => :manage_password
    else
      @menu = 'manage_password'
      render :partial => 'manage_password', :layout => 'layout'
    end
  end

  def apply_email
    if @applied_email = AppliedEmail.find_by_user_id(session[:user_id])
      @applied_email.email = params[:applied_email][:email]
    else
      @applied_email = AppliedEmail.new(params[:applied_email])
      @applied_email.user_id = session[:user_id]
    end

    if @applied_email.save
      UserMailer::Smtp.deliver_sent_apply_email_confirm(@applied_email.email, "#{root_url}mypage/update_email/#{@applied_email.onetime_code}/")
      flash.now[:notice] = _("Your request of changing email address accepted. Check your email to complete the process.")
    else
      flash.now[:warn] = _("Failed to process your request. Try resubmitting your request again.")
    end
    @menu = 'manage_email'
    @user = current_user
    render :partial => 'manage_email', :layout => "layout"
  end

  def update_email
    if @applied_email = AppliedEmail.find_by_user_id_and_onetime_code(session[:user_id], params[:id])
      @user = current_user
      old_email = @user.email
      @user.email = @applied_email.email
      if @user.save
        @applied_email.destroy
        flash[:notice] = _("Email address was updated successfully.")
        redirect_to :action => 'profile'
      else
        @user.email = old_email
        @menu = 'manage_email'
        flash[:notice] = _("The specified email address has already been registered. Try resubmitting the request with another address.")
        render :partial => 'manage_email', :layout => "layout"
      end
    else
      flash[:notice] = _('Specified page not found.')
      redirect_to :action => 'index'
    end
  end

  def apply_ident_url
    redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:free_rp)
    @openid_identifier = current_user.openid_identifiers.first || current_user.openid_identifiers.build
    if using_open_id?
      begin
        authenticate_with_open_id do |result, identity_url|
          if result.successful?
            @openid_identifier.url = identity_url
            if @openid_identifier.save
              flash[:notice] = _('OpenID URL was successfully set.')
              redirect_to :action => :manage, :menu => :manage_openid
              return
            else
              render :partial => 'manage_openid', :layout => 'layout'
            end
          else
            flash.now[:error] = _("OpenId process is cancelled or failed.")
            render :partial => 'manage_openid', :layout => 'layout'
          end
        end
      rescue OpenIdAuthentication::InvalidOpenId
        flash.now[:error] = _("Invalid OpenID URL format.")
        render :partial => 'manage_openid', :layout => 'layout'
      end
    else
      flash.now[:error] = _("Please input OpenID URL.")
      render :partial => 'manage_openid', :layout => 'layout'
    end
  end

  # POST or PUT action
  def update_customize
    @user_custom = current_user.custom
    if @user_custom.update_attributes(params[:user_custom])
      setup_custom_cookies
      flash[:notice] = _('Updated successfully.')
      redirect_to :action => 'manage', :menu => 'manage_customize'
    else
      render :partial => 'manage_customize', :layout => "layout"
    end
  end

  private
  # [最近]を表す日数
  def recent_day
    10
  end

  def setup_layout
    @main_menu = @title = _('My Page')
  end

  def find_antennas
    Antenna.find_with_counts current_user
  end

  # 日付情報を解析して返す。
  def parse_date
    year = params[:year] ? params[:year].to_i : Time.now.year
    month = params[:month] ? params[:month].to_i : Time.now.month
    day = params[:day] ? params[:day].to_i : Time.now.day
    unless Date.valid_date?(year, month, day)
      year, month, day = Time.now.year, Time.now.month, Time.now.day
    end
    return year, month, day
  end

  def antenna_entry(key, read = true)
    unless key.blank?
      begin
        key = Integer(key)
        UserAntennaEntry.new(current_user, key, read)
      rescue ArgumentError
        if %w(message comment bookmark group).include?(key)
          SystemAntennaEntry.new(current_user, key, read)
        else
          raise ActiveRecord::RecordNotFound
        end
      end
    else
      AntennaEntry.new(current_user, read)
    end
  end

  class AntennaEntry
    attr_reader :key, :antenna
    attr_accessor :title

    def initialize(current_user, read = true)
      @read = read
      @current_user = current_user
    end

    def conditions
      find_params = {:conditions => [['']], :include => []}
      find_params = BoardEntry.make_conditions(@current_user.belong_symbols, {})

      unless @read
        find_params[:conditions][0] << " and user_readings.read = ? and user_readings.user_id = ?"
        find_params[:conditions] << false << @current_user.id
        find_params[:include] << :user_readings
      end
      find_params
    end

    def need_search?
      true
    end
  end

  class SystemAntennaEntry < AntennaEntry
    def initialize(current_user, key, read = true)
      @current_user = current_user
      @key = key
      @read = read
    end

    def conditions
      find_params = {:conditions => [['']], :include => []}
      case
      when @key == 'message'  then find_params = conditions_for_entries_by_system_antenna_message
      when @key == 'comment'  then find_params = conditions_for_entries_by_system_antenna_comment
      when @key == 'bookmark' then find_params = conditions_for_entries_by_system_antenna_bookmark
      when @key == 'group'    then find_params = conditions_for_entries_by_system_antenna_group
      end

      unless @read
        find_params[:conditions][0] << " and user_readings.read = ? and user_readings.user_id = ?"
        find_params[:conditions] << false << @current_user.id
        find_params[:include] << :user_readings
      end
      find_params
    end

    def need_search?
      !(@key == 'group' && @current_user.group_symbols.size == 0)
    end

    private
    # #TODO BoardEntryに移動する
    # システムアンテナ[message]の記事を取得するための検索条件
    def conditions_for_entries_by_system_antenna_message
      BoardEntry.make_conditions @current_user.belong_symbols, { :category=>'連絡' }
    end

    # #TODO BoardEntryに移動する
    # システムアンテナ[comment]の記事を取得するための検索条件
    def conditions_for_entries_by_system_antenna_comment
      find_params = BoardEntry.make_conditions(@current_user.belong_symbols)
      find_params[:conditions][0] << " and board_entry_comments.user_id = ?"
      find_params[:conditions] << @current_user.id
      find_params[:include] << :board_entry_comments
      find_params
    end

    # #TODO BoardEntryに移動する
    # システムアンテナ[bookmark]の記事を取得するための検索条件
    def conditions_for_entries_by_system_antenna_bookmark
      bookmarks = Bookmark.find(:all,
                                :conditions => ["bookmark_comments.user_id = ? and bookmarks.url like '/page/%'", @current_user.id],
                                :include => [:bookmark_comments])
      ids = []
      bookmarks.each do |bookmark|
        ids << bookmark.url.gsub(/\/page\//, "")
      end

      find_params = BoardEntry.make_conditions(@current_user.belong_symbols)
      find_params[:conditions][0] << " and board_entries.id in (?)"
      find_params[:conditions] << ids
      find_params
    end

    # #TODO BoardEntryに移動する
    # システムアンテナ[group]の記事を取得するための検索条件
    def conditions_for_entries_by_system_antenna_group
      BoardEntry.make_conditions @current_user.belong_symbols, { :symbols => @current_user.group_symbols }
    end
  end

  class UserAntennaEntry < AntennaEntry
    def initialize(current_user, key, read = true)
      @current_user = current_user
      @key = key
      @read = read
      @antenna = Antenna.find(@key)
      @title = @antenna.name
    end

    def conditions
      symbols, keyword = @antenna.get_search_conditions
      find_params = {:conditions => [['']], :include => []}
      find_params = BoardEntry.make_conditions(@current_user.belong_symbols, :symbols => symbols, :keyword => keyword)

      unless @read
        find_params[:conditions][0] << " and user_readings.read = ? and user_readings.user_id = ?"
        find_params[:conditions] << false << @current_user.id
        find_params[:include] << :user_readings
      end
      find_params
    end

    def need_search?
      @antenna_items = @antenna.antenna_items
      @antenna_items && @antenna_items.size > 0
    end
  end

  # TODO helperに移動することを検討
  # mypage > home の システムメッセージの配列
  def system_messages
    system_messages = []
    unless current_user.picture
      system_messages << {
        :text => _("Change your profile picture!"), :icon => "picture",
        :option => {:controller => "mypage", :action => "manage", :menu => "manage_portrait"}
      }
    end
    system_messages
  end

  # TODO BoardEntryに移動する
  # あなたへの連絡(公開, 未読/既読は関係なし、最近のもののみ)が設定されること
  def important_your_messages
    find_params = BoardEntry.make_conditions(login_user_symbols, {:recent_day => recent_day, :publication_type => "public", :category => "連絡"})
    BoardEntry.scoped(
      :conditions=> find_params[:conditions],
      :include => find_params[:include] | [ :user, :state ]
    ).order_new.all
  end

  # TODO BoardEntryに移動する
  # あなたへの連絡（非公開・未読のもののみ）
  def mail_your_messages
    find_params = BoardEntry.make_conditions(login_user_symbols, {:category=>'連絡'})
    find_params[:conditions][0] << " and publication_type in (?) and user_readings.read = ? and user_readings.user_id = ?"
    find_params[:conditions] << %w(private protected) << false << current_user.id
    find_params[:include] << :user_readings
    { :id_name => 'message',
      :title_icon => "email",
      :title_name => _("Messages for you"),
      :pages => BoardEntry.scoped(
        :conditions=> find_params[:conditions],
        :include => find_params[:include] | [ :user, :state ]
      ).order_new.all,
      :delete_categories => '[連絡]' }
  end

  def find_as_locals target, options
    group_categories = GroupCategory.all.map{ |gc| gc.code.downcase }
    case
    when target == 'questions'             then find_questions_as_locals options
    when target == 'access_blogs'          then find_access_blogs_as_locals options
    when target == 'recent_blogs'          then find_recent_blogs_as_locals options
    when group_categories.include?(target) then find_recent_bbs_as_locals target, options
# TODO 例外出すなどの対応をしないとアプリケーションエラーになってしまう。
#    else
    end
  end

  # 質問記事一覧を取得する（partial用のオプションを返す）
  def find_questions_as_locals options
    pages = BoardEntry.accessible(current_user).recent(options[:recent_day]).category_like('質問').
      category_not_like('解決').order_new.paginate(:page => params[:page], :per_page => options[:per_page])

    locals = {
      :id_name => 'questions',
      :title_icon => "user_comment",
      :title_name => _('Recent Questions'),
      :pages => pages,
      :per_page => options[:per_page],
      :recent_day => options[:recent_day],
      :delete_categories => '[質問]'
    }
  end

  # 最近の人気記事一覧を取得する（partial用のオプションを返す）
  def find_access_blogs_as_locals options
    find_params = BoardEntry.make_conditions(login_user_symbols, {:publication_type => 'public'})
    find_params[:conditions][0] << " and board_entries.category not like ? and last_updated > ?"
    find_params[:conditions] << '%[質問]%' << Date.today - recent_day
    pages = BoardEntry.scoped(
      :conditions => find_params[:conditions],
      :order => "board_entry_points.today_access_count DESC, board_entry_points.access_count DESC, board_entries.last_updated DESC, board_entries.id DESC",
      :include => find_params[:include] | [ :user, :state ]
    ).paginate(:page => params[:page], :per_page => options[:per_page])

    locals = {
      :id_name => 'access_blogs',
      :title_icon => "star",
      :title_name => _('Recent Popular Entries (excluding questions)'),
      :pages => pages,
      :per_page => options[:per_page],
      :symbol2name_hash => BoardEntry.get_symbol2name_hash(pages)
    }
  end

  # 記事一覧を取得する（partial用のオプションを返す）
  def find_recent_blogs_as_locals options
    find_params = BoardEntry.make_conditions(login_user_symbols, {:entry_type=>'DIARY', :publication_type => 'public'})
    pages = BoardEntry.scoped(
      :conditions => find_params[:conditions],
      :include => find_params[:include] | [ :user, :state ]
    ).order_new.paginate(:page => params[:page], :per_page => options[:per_page])

    locals = {
      :id_name => 'recent_blogs',
      :title_icon => "user",
      :title_name => _('Blogs'),
      :pages => pages,
      :per_page => options[:per_page]
    }
  end

  # BBS記事一覧を取得するメソッドを動的に生成(partial用のオプションを返す)
  def find_recent_bbs_as_locals code, options = {}
    category = GroupCategory.find_by_code(code)
    title   = category.name
    id_name = category.code.downcase
    pages = []

    find_options = {:exclude_entry_type=>'DIARY'}
    find_options[:symbols] = options[:group_symbols] || Group.gid_by_category[category.id]
    if find_options[:symbols].size > 0
      find_params = BoardEntry.make_conditions(login_user_symbols, find_options)
      pages = BoardEntry.scoped(
        :conditions => find_params[:conditions],
        :include => find_params[:include] | [ :user, :state ]
      ).order_new.paginate(:page => params[:page], :per_page => options[:per_page])
    end
    locals = {
      :id_name => id_name,
      :title_icon => "group",
      :title_name => title,
      :pages => pages,
      :per_page => options[:per_page],
      :symbol2name_hash => BoardEntry.get_symbol2name_hash(pages)
    }
  end

  def recent_bbs
    recent_bbs = []
    gid_by_category = Group.gid_by_category
    GroupCategory.all.each do |category|
      options = { :group_symbols => gid_by_category[category.id], :per_page => 8 }
      recent_bbs << find_recent_bbs_as_locals(category.code.downcase, options)
    end
    recent_bbs
  end

  def current_user_antennas_as_json
    antennas = Antenna.all(:conditions => ["user_id = ?" , current_user.id])
    result = {
      :antenna_list => antennas.map do |antenna|
        { :name => antenna.name, :url => url_for(:controller => :feed, :action => :user_antenna, :id => antenna.id) }
      end
    }.to_json
  end

  def unify_feed_form feed, title = nil, limit = nil
    feed = feed.to_rss("2.0") if !feed.is_a?(RSS::Rss) and feed.is_a?(RSS::Atom::Feed)

    feed.channel.title = title if title
    limit = (limit || Admin::Setting.mypage_feed_default_limit)
    feed.items.slice!(limit..-1) if feed.items.size > limit
    feed
  rescue NameError => e
    logger.error "[Error] Atom conversion failed due to outdated ruby libraries."
    return nil
  end

  # TODO #924で画面からリンクをなくした。1.4時点で復活しない場合は削除する
  def set_data_for_record_mail
    @pages, @mails = paginate(:mail,
                              :per_page =>20,
                              :select => "*, mails.updated_on as mail_updated_on",
                              :conditions => ["mails.from_user_id = ?", session[:uid]],
                              :order_by => "mails.id DESC")

    #タイトルのリンクができるかできないかを判定する材料を取得する(ヘルパーで使う)
    user_entry_no_list = @mails.map{ |mail| mail.user_entry_no }
    if user_entry_no_list.size > 0
      board_entries = BoardEntry.find(:all, :conditions =>["user_id = ? and user_entry_no in (?)",  session[:user_id], user_entry_no_list])
      @board_enries_by_user_entry_no = Hash.new
      board_entries.each{ |board_entry| @board_enries_by_user_entry_no.store(board_entry.user_entry_no, board_entry) }
    end

    #送信先のリンクができるかできないかを判定する材料を取得する(ヘルパーで使う)
    uid_list = gid_list = []
    for mail in @mails
      id = mail.symbol_id
      case mail.symbol_type
      when 'uid'
        uid_list << id
      when 'gid'
        gid_list << id
      end
    end

    @exist_item_by_symbol = Hash.new
    if uid_list.size > 0
      users = User.find(:all, :conditions =>['user_uids.uid in (?)', uid_list], :include => [:user_uids])
      users.each{ |user|  @exist_item_by_symbol.store(user.symbol, user) }
    end
    if gid_list.size > 0
      groups = Group.active.find(:all, :conditions =>['gid in (?)', gid_list])
      groups.each{ |group|  @exist_item_by_symbol.store(group.symbol, group) }
    end
  end

  # TODO #924で画面からリンクをなくした。1.4時点で復活しない場合は削除する
  def set_data_for_record_blog
    login_user_id = session[:user_id]

    options = {}
    options[:writer_id] = login_user_id
    options[:keyword] = params[:keyword]
    options[:category] = params[:category]
    find_params = BoardEntry.make_conditions(login_user_symbols, options)

    @pages, @board_entries = paginate(:board_entry,
                                      :per_page => 20,
                                      :order => "last_updated DESC,board_entries.id DESC",
                                      :conditions => find_params[:conditions],
                                      :include => find_params[:include])

    @symbol2name_hash = BoardEntry.get_symbol2name_hash @board_entries

    find_params = BoardEntry.make_conditions(login_user_symbols, {:writer_id => login_user_id})
    @categories = BoardEntry.get_category_words(find_params)
  end

  def get_url_hash action, options = {}
    login_user_symbol_type, login_user_symbol_id = Symbol.split_symbol(session[:user_symbol])
    { :controller => 'user', :action => action, :uid => login_user_symbol_id }.merge options
  end

  # 月の中で記事が含まれている日付と記事数のハッシュと、
  # 引数は、指定の年と月
  def get_entry_count year, month
    find_params = BoardEntry.make_conditions(login_user_symbols, {:entry_type=>'DIARY'})
    find_params[:conditions][0] << " and YEAR(date) = ? and MONTH(date) = ?"
    find_params[:conditions] << year << month

    entry_count = {}
    entry_days = BoardEntry.find(:all,
                                 :select => "DAY(date) as date_, count(board_entries.id) as count",
                                 :order => "date_ ASC",
                                 :group => "date_",
                                 :conditions=> find_params[:conditions],
                                 :joins => "LEFT OUTER JOIN entry_publications ON entry_publications.board_entry_id = board_entries.id")
    entry_days.each do |item|
      entry_count[item.date_.to_i] = item.count
    end
    return entry_count
  end

  def valid_list_types
    %w(questions access_blogs recent_blogs) | GroupCategory.all.map{ |gc| gc.code.downcase }
  end

  # TODO BoardEntryに移動する
  # 指定日の記事一覧を取得する
  def find_entries_at_specified_date(selected_day)
    find_params = BoardEntry.make_conditions(login_user_symbols, {:entry_type=>'DIARY'})
    find_params[:conditions][0] << " and DATE(date) = ?"
    find_params[:conditions] << selected_day
    BoardEntry.find(:all, :conditions=> find_params[:conditions], :order=>"date ASC",
                          :include => find_params[:include] | [ :user, :state ])
  end

  # TODO BoardEntryに移動する
  # 指定日以降で最初に記事が存在する日
  def first_entry_day_after_specified_date(selected_day)
    find_params = BoardEntry.make_conditions(login_user_symbols, {:entry_type=>'DIARY'})
    find_params[:conditions][0] << " and DATE(date) > ?"
    find_params[:conditions] << selected_day
    next_day = BoardEntry.find(:first, :select => "date, DATE(date) as count_date, count(board_entries.id) as count",
                               :conditions=> find_params[:conditions],
                               :group => "count_date",
                               :order => "date ASC",
                               :limit => 1,
                               :joins => "LEFT OUTER JOIN entry_publications ON entry_publications.board_entry_id = board_entries.id")
    next_day ? next_day.date : nil
  end

  # TODO BoardEntryに移動する
  # 指定日以前で最後に記事が存在する日
  def last_entry_day_before_specified_date(selected_day)
    find_params = BoardEntry.make_conditions(login_user_symbols, {:entry_type=>'DIARY'})
    find_params[:conditions][0] << " and DATE(date) < ?"
    find_params[:conditions] << selected_day
    prev_day = BoardEntry.find(:first, :select => "date, DATE(date) as count_date, count(board_entries.id) as count",
                               :conditions=> find_params[:conditions],
                               :group => "count_date",
                               :order => "date DESC",
                               :limit => 1,
                               :joins => "LEFT OUTER JOIN entry_publications ON entry_publications.board_entry_id = board_entries.id")
    prev_day ? prev_day.date : nil
  end

  # TODO helperへ移動する
  # アンテナの記事一覧のタイトル
  def antenna_entry_title(antenna_entry)
    if antenna = antenna_entry.antenna
      antenna.name
    else
      key = antenna_entry.key
      case
      when key == 'message'  then _("Messages for you")
      when key == 'comment'  then _("Entries you have made comments")
      when key == 'bookmark' then _("Entries bookmarked by yourself")
      when key == 'group'    then _("Posts in the groups joined")
      else
        _('List of unread entries')
      end
    end
  end

  # TODO UserReadingに移動する
  # 指定した記事idのをキーとした未読状態のUserReadingのハッシュを取得
  def unread_entry_id_hash_with_user_reading(entry_ids)
    result = {}
    if entry_ids && entry_ids.size > 0
      user_readings_conditions = ["user_id = ? and board_entry_id in (?)"]
      user_readings_conditions << current_user.id << entry_ids
      user_readings = UserReading.find(:all, :conditions => user_readings_conditions)
      user_readings.each do |user_reading|
        result[user_reading.board_entry_id] = user_reading unless user_reading.read
      end
    end
    result
  end

  def load_user
    @user = current_user
  end
end
