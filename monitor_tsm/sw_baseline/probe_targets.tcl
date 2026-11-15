if {[catch {connect} e]} {puts "NOCONN $e"; exit}
after 1500
puts [targets]
exit
