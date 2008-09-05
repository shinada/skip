# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008 TIS Inc.
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

class Admin::Bookmark < Bookmark
  has_many :bookmark_comments, :class_name => 'Admin::BookmarkComment'
  N_('Admin::Bookmark|Title')
  N_('Admin::Bookmark|Url')

  def self.search_colomns
    "title like :lqs or url like :lqs"
  end

  def topic_title
    title[/.{1,10}/] + "..."
  end
end
