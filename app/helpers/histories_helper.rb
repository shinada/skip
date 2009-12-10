module HistoriesHelper
  def link_to_next_diff(histories, a_history, page = @current_page)
    if a_history == histories.first
      "-"
    else
      pos = histories.index(a_history)
      link_to(_("次"), diff_url(page, histories[pos - 1], a_history))
    end
  end

  def link_to_previous_diff(histories, a_history, page = @current_page)
    if a_history == histories.last
      "-"
    else
      pos = histories.index(a_history)
      link_to(_("前"), diff_url(page, histories[pos + 1], a_history))
    end
  end

  def diff_symbol(symbol, css=true)
    sym = case symbol
          when "=" then ""
          when "-" then "removed"
          when "+" then "added"
          when "!" then "modified"
          end
    css ? sym : sym[0,1].upcase
  end

  def explain_history(history)
    hist = {
      :rev =>  content_tag("span", @history.revision, :class => "val"),
      :user=>  content_tag("span", @history.user.name, :class => "val"),
      :date => content_tag("span", @history.updated_at.strftime("%Y/%m/%d %H:%M"), :class => "val"),
    }

    sanitize( _("リビジョン#{hist[:rev]}を表示しています。  (#{hist[:user]}さんが#{hist[:date]}に更新しました。)") % hist)
  end

  def decode_nbsp(string)
    nbsp = [0xA0].pack("U")
    return nbsp if string.blank?
    string.gsub(/&nbsp;/, nbsp).gsub(/&gt;/, ">").gsub(/&lt;/, "<")
  end

  private
  def diff_url(page, from, to)
    diff_wiki_histories_path(page.title, {:from => from.revision, :to => to.revision})
  end
end
