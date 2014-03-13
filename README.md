
http.bash
=========

`http.bash` is the minimalistic HTTP server mostly written in bash.

I tried to minimize external dependencies if possible.  Though, it has dependencies of `readlink(1)`, `dd(1)` and `cat(1)`.

Currently, it supports following HTTP requests; GET, HEAD, POST


Running
-------

You need either [`tcpserver`](http://cr.yp.to/ucspi-tcp/tcpserver.html) or [`nc`](http://nc110.sourceforge.net/) (a.k.a., netcat).

To support more than one connection, you'l need `tcpserver` rather than `nc`.  Note that some BSD version of `nc` is not supported.  (If `nc -h` does not shows `-e` option, your version is probably BSD one.)

    $ tcpserver 0 8080 ./http.bash
    
    Or

    $ while :; do nc -l -p 8080 -e ./http.bash; done
    
