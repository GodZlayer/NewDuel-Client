import sqlite3
import sys

user = sys.argv[1]
db_path = sys.argv[2]

con = sqlite3.connect(db_path)
count = con.execute("SELECT COUNT(*) FROM Account WHERE UserID=?", (user,)).fetchone()[0]
print(count)
