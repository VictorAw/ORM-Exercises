CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  fname VARCHAR(255) NOT NULL,
  lname VARCHAR(255) NOT NULL
);

CREATE TABLE questions (
  id INTEGER PRIMARY KEY,
  title VARCHAR(255) not null,
  body TEXT,
  author_id INTEGER not null,

  FOREIGN KEY (author_id) REFERENCES users(id)
);

CREATE TABLE question_follows (
  user_id INTEGER NOT NULL,
  question_id INTEGER NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (question_id) REFERENCES questions(id)
);

CREATE TABLE replies (
  id INTEGER PRIMARY KEY,
  question_id INTEGER NOT NULL,
  parent_id INTEGER,
  author_id INTEGER NOT NULL,
  body TEXT,

  FOREIGN KEY (question_id) REFERENCES questions(id)
  FOREIGN KEY (parent_id) REFERENCES replies(id)
  FOREIGN KEY (author_id) REFERENCES users(id)
);

CREATE TABLE question_likes (
  user_id INTEGER NOT NULL,
  question_id INTEGER NOT NULL,

  FOREIGN KEY (question_id) REFERENCES questions(id)
  FOREIGN KEY (user_id) REFERENCES users(id)
);

INSERT INTO
  users (fname, lname)
VALUES
  ('Victor', 'Aw'),('Ben', 'Dippelsman');

INSERT INTO
  questions (title, body, author_id)
VALUES
  ('ruby install help', 'not working', (SELECT id FROM users WHERE fname = 'Victor' AND lname = 'Aw'));

INSERT INTO
  question_follows(user_id,question_id)
VALUES
  (1,1),(2,1);

INSERT INTO
  question_likes(user_id,question_id)
VALUES
  (1,1),(2,1);

INSERT INTO
  replies(question_id,parent_id,author_id,body)
VALUES
  (1,null,2,'soz bb'),(1,1,2,'jk'),(1,null,1,'ok');
