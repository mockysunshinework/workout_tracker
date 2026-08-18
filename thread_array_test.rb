ready = Queue.new
start = Queue.new

threads = Array.new(2) do |i|
  Thread.new do
    puts "Thread #{i}：準備します"

    ready << true

    puts "Thread #{i}：スタート待ち"
    start.pop

    puts "Thread #{i}：処理開始！"
  end
end

ready.pop
ready.pop

puts "親：2人とも準備完了"

start << true
start << true

threads.each(&:value)

puts "親：全部終了"
