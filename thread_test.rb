ready = Queue.new
start = Queue.new

thread1 = Thread.new do
  puts "A：準備中"

  ready << true

  puts "A：スタート待ち"
  start.pop

  puts "A：走った！"
end

thread2 = Thread.new do
  puts "B：準備中"

  ready << true

  puts "B：スタート待ち"
  start.pop

  puts "B：走った！"
end

# 2人から「準備OK」が来るまで待つ
ready.pop
ready.pop

puts "親：2人とも準備できた！"

# 2人にスタート合図
start << true
start << true

thread1.value
thread2.value
