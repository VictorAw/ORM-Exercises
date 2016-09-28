require "singleton"
require 'sqlite3'
require 'byebug'

class QuestionsDatabase < SQLite3::Database
  include Singleton

  def initialize
    super('questions.db')
    self.type_translation = true
    self.results_as_hash = true
  end
end

def tableize(str)
  if str[-1] == 'y'
    str.downcase.chop + "ies"
  else
    str.downcase + "s"
  end
end

# Kind of works
def sanitize(str)
  str.delete(";")
end

def make_query(table, where)
  "SELECT\
      *\
    FROM\
      #{tableize(table)}\
    WHERE\
      #{where}"
end

def remove_repeats(objs)
  i = 0
  j = i+1
  while i < objs.size-1
    while j < objs.size
      i_keys = objs[i].instance_variables
      i_vals = objs[i].get_instance_variables
      j_keys = objs[j].instance_variables
      j_vals = objs[j].get_instance_variables
      if i_vals == j_vals && i_keys == j_keys
        objs.delete_at(j)
        j -= 1
      end

      j += 1
    end
    i += 1
  end

  return nil if objs.empty?

  objs
end

class ModelBase
  attr_accessor :id, :table

  def self.where(options)
    res = []
    db = QuestionsDatabase.instance
    if options.is_a?(String)
      options = sanitize(options)
      query = make_query(self.to_s, options)
      base = db.execute(query)
      res += base
    else
      options.each do |column,val|
        column = column.to_s
        column = sanitize(column)
        val = sanitize(val)
        query = make_query(self.to_s, "#{column} = #{val}")
        base = db.execute(query)
        res += base
      end
    end
    objs = res.map {|option| self.new(option)}

    remove_repeats(objs)

  end

  def initialize(options)
    @id = options['id']
  end

  def [](key)
    return instance_variable_get(key)
  end

  def get_instance_variables
    ret = []
    instance_variables.each { |key| ret << self[key] }
    ret
  end

  def self.method_missing(method_name, *args)
    method_name = method_name.to_s
    if method_name.start_with?("find_by_")
      # attributes_string is, e.g., "first_name_and_last_name"
      attributes_string = method_name[("find_by_".length)..-1]

      # attribute_names is, e.g., ["first_name", "last_name"]
      attribute_names = attributes_string.split("_and_")

      unless attribute_names.length == args.length
        raise "unexpected # of arguments"
      end

      search_conditions = {}
      attribute_names.each_index do |i|
        search_conditions[attribute_names[i]] = args[i]
      end

      # Imagine search takes a hash of search conditions and finds
      # objects with the given properties.
      obj = self.where(search_conditions)

      return nil unless obj
      return obj.first if obj.size == 1

      obj
    else
      # complain about the missing method
      super
    end
  end
end

class User < ModelBase
  attr_accessor :id, :fname, :lname

  def self.find_by_name(fname, lname)
    user = QuestionsDatabase.instance.execute(<<-SQL, fname, lname)
      SELECT
        *
      FROM
        users
      WHERE
        fname = ? AND lname = ?
    SQL
    return nil unless user.length > 0

    User.new(user.first)
  end

  def initialize(options)
    super
    @fname = options['fname']
    @lname = options['lname']
  end

  def authored_questions
    Question.find_by_author_id(@id)
  end

  def authored_replies
    Reply.find_by_author_id(@id)
  end

  def followed_questions
    QuestionFollow.followed_questions_for_user_id(@id)
  end

  def liked_questions
    QuestionLike::liked_questions_for_user_id(@id)
  end

  def average_karma
    karma_hash = QuestionsDatabase.instance.execute(<<-SQL, @id)
      SELECT
        -- COUNT(DISTINCT(questions.id)) AS avg_karma -- Works
        -- COUNT(DISTINCT(*)) AS avg_karma            -- Syntax Error
        (COUNT(question_likes.user_id) / NULLIF(COUNT(DISTINCT(questions.id)), 0)) AS avg_karma
          -- COUNT(DISTINCT(*)) AS avg_karma -- Cannot DISTINCT or alias *
      FROM
        questions
        LEFT OUTER JOIN
          question_likes ON questions.id = question_likes.question_id
      WHERE
        questions.author_id = ?
    SQL

    avg_karma = karma_hash.first['avg_karma']

    return avg_karma if avg_karma
    0
  end

  def create
    QuestionsDatabase.instance.execute(<<-SQL,@fname, @lname)
      INSERT INTO
        users(fname,lname)
      VALUES
        (?, ?)
    SQL
    @id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL,@fname, @lname, @id)
      UPDATE
        users
      SET
        fname = ?, lname = ?
      WHERE
        id = ?
    SQL
  end

  def save
    @id.nil? ? create : update
  end
end

class Question < ModelBase
  attr_accessor :id, :title, :body, :author_id

  def self.find_by_title(title)
    question = QuestionsDatabase.instance.execute(<<-SQL, title)
      SELECT
        *
      FROM
        questions
      WHERE
        title = ?
    SQL
    return nil unless question.length > 0

    question.map { |datum| Question.new(datum) }
  end

  def self.find_by_author_id(author_id)
    question = QuestionsDatabase.instance.execute(<<-SQL, author_id)
      SELECT
        *
      FROM
        questions
      WHERE
        author_id = ?
    SQL
    return nil unless question.length > 0

    question.map { |datum| Question.new(datum) }
  end

  def self.most_followed(n)
      QuestionFollow.most_followed_questions(n)
  end

  def self.most_liked(n)
    QuestionLike.most_liked_questions(n)
  end

  # def self.find_by_author_name(fname, lname)
  #   question = QuestionsDatabase.instance.execute(<<-SQL, fname,lname)
  #     SELECT
  #       id, title, body, author_id
  #     FROM
  #       questions
  #       JOIN users on author_id = users.id
  #     WHERE
  #       users.fname = ? AND users.lname = ?
  #   SQL
  #   return nil unless question.length > 0
  #
  #   Question.new(question.first)
  # end

  def initialize(options)
    super
    @title = options['title']
    @body = options['body']
    @author_id = options['author_id']
  end

  def author
    User.find_by_id(@author_id)
  end

  def replies
    Reply.find_by_question_id(@id)
  end

  def followers
    QuestionFollow.followers_for_question_id(@id)
  end

  def likers
    QuestionLike::likers_for_question_id(@id)
  end

  def num_likes
    QuestionLIkes::num_likes_for_question_id(@id)
  end

  def create
    QuestionsDatabase.instance.execute(<<-SQL,@title, @body, @author_id)
      INSERT INTO
        questions(title,body,author_id)
      VALUES
        (?, ?, ?)
    SQL
    @id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL,@title, @body, @author_id, @id)
      UPDATE
        questions
      SET
        title = ?, body = ?, author_id = ?
      WHERE
        id = ?
    SQL
  end

  def save
    @id.nil? ? create : update
  end
end

class QuestionFollow
  attr_accessor :id, :user_id, :question_id

  def self.find_by_id(id)
    question_follow = QuestionsDatabase.instance.execute(<<-SQL, id)
      SELECT
        *
      FROM
        question_follows
      WHERE
        id = ?
    SQL
    return nil unless question_follow.length > 0

    QuestionFollow.new(question_follow.first)
  end

  def self.followers_for_question_id(question_id)
    followers = QuestionsDatabase.instance.execute(<<-SQL, question_id)
      SELECT
        users.*
      FROM
        question_follows
        JOIN
          users ON question_follows.user_id = users.id
      WHERE
        question_follows.question_id = ?
    SQL
    return nil unless followers.length > 0

    followers.map { |follower| User.new(follower) }
  end

  def self.followed_questions_for_user_id(user_id)
    questions = QuestionsDatabase.instance.execute(<<-SQL, user_id)
      SELECT
        questions.*
      FROM
        question_follows
        JOIN
          questions ON question_follows.user_id = questions.id
      WHERE
        question_follows.user_id = ?
    SQL
    return nil unless questions.length > 0

    questions.map { |question| Question.new(question) }
  end

  def self.most_followed_questions(n)
      questions = QuestionsDatabase.instance.execute(<<-SQL, n)
        SELECT
          questions.*
        FROM
          question_follows
        JOIN
          questions ON questions.id = question_follows.question_id
        GROUP BY
          question_follows.question_id
        ORDER BY
          COUNT(*)
        LIMIT
          ?
      SQL
      return nil unless questions.length > 0

      questions.map { |question| Question.new(question) }
  end

  def intialize(options)
    @id = options['id']
    @user_id = options['user_id']
    @question_id = options['question_id']
  end
end

class Reply < ModelBase
  attr_accessor :id, :question_id, :parent_id, :author_id, :body

  def self.find_by_user_id(user_id)
    replies = QuestionsDatabase.instance.execute(<<-SQL, user_id)
      SELECT
        replies.*
      FROM
        replies
      WHERE
        author_id = ?
    SQL
    return nil unless replies.length > 0

    replies.map do |reply|
      Reply.new(reply)
    end
  end

  def self.find_by_question_id(question_id)
    replies = QuestionsDatabase.instance.execute(<<-SQL, question_id)
      SELECT
        *
      FROM
        replies
      WHERE
        question_id = ?
    SQL
    return nil unless replies.length > 0

    replies.map { |reply| Reply.new(reply) }
  end

  def self.find_by_parent_id(parent_id)
    replies = QuestionsDatabase.instance.execute(<<-SQL, parent_id)
      SELECT
        *
      FROM
        replies
      WHERE
        parent_id = ?
    SQL
    reutrn nil unless replies.length > 0

    replies.map { |reply| Reply.new(reply) }
  end

  def initialize(options)
    super
    @question_id = options['question_id']
    @parent_id = options['parent_id']
    @author_id = options['author_id']
    @body = options['body']
  end

  def author
    User.find_by_id(@author_id)
  end

  def question
    Question.find_by_id(@question_id)
  end

  def parent_reply
    Reply.find_by_id(@parent_id)
  end

  def child_replies
    Reply.find_by_parent_id(@id)
  end

  def create
    QuestionsDatabase.instance.execute(<<-SQL,@question_id, @parent_id, @author_id, @body)
      INSERT INTO
        replies(question_id,parent_id,author_id, body)
      VALUES
        (?, ?, ?,?)
    SQL
    @id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL,@question_id, @parent_id, @author_id, @body, @id)
      UPDATE
        questions
      SET
        question_id = ?, parent_id = ?, author_id = ?, body = ?
      WHERE
        id = ?
    SQL
  end

  def save
    @id.nil? ? create : update
  end
end

class QuestionLike
  attr_accessor :id, :question_id, :user_id

  def self.find_by_id(id)
    question_like = QuestionsDatabase.instance.execute(<<-SQL, id)
      SELECT
        *
      FROM
        question_likes
      WHERE
        id = ?
    SQL
    return nil unless question_like.length > 0

    QuestionLike.new(question_like.first)
  end

  def self.likers_for_question_id(question_id)
    likers = QuestionsDatabase.instance.execute(<<-SQL, question_id)
    SELECT
      users.*
    FROM
      question_likes
      JOIN
      users ON question_likes.user_id = users.id
    WHERE
      question_likes.question_id = ?
    SQL

    return nil if likers.length <1

    likers.map {|user| User.new(user)}
  end

  def self.num_likes_for_question_id(question_id)
    num_likes = QuestionsDatabase.instance.execute(<<-SQL, question_id)
    SELECT
      COUNT(*) as n
    FROM
      question_likes
    WHERE
      question_id = ?
    GROUP BY
      question_id

    SQL

    num_likes.first['n']
  end

  def self.liked_questions_for_user_id(user_id)
    liked_questions = QuestionsDatabase.instance.execute(<<-SQL, user_id)
    SELECT
      questions.*
    FROM
      users
      JOIN
        question_likes ON question_likes.user_id = users.id
      JOIN
        questions ON questions.id = questions_likes.question_id
    WHERE
      question_likes.user_id = ?
    SQL

    return nil if liked_questions.length <1

    liked_questions.map {|question| Question.new(question)}
  end

  def self.most_liked_questions(n)
      questions = QuestionsDatabase.instance.execute(<<-SQL, n)
        SELECT
          questions.*
        FROM
          question_likes
        JOIN
          questions ON questions.id = question_likes.question_id
        GROUP BY
          question_likes.question_id
        ORDER BY
          COUNT(*)
        LIMIT
          ?
      SQL
      return nil unless questions.length > 0

      questions.map { |question| Question.new(question) }
  end

  def initialize(options)
    @id = options['id']
    @question_id = options['question_id']
    @user_id = options['user_id']
  end
end

if __FILE__ == $PROGRAM_NAME
  p User.where("fname = 'Victor'")
  # p User.find_by_id(1)
  # p Reply.find_by_id(3).parent_reply
  # p User.where({fname: 'Victor', lname: 'Aw'})
  # # p QuestionLike.num_likes_for_question_id(1)
  # p User.find_by_id(1).average_karma
  # p User.find_by_id(2).average_karma

end
