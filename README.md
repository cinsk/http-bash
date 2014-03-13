
http.bash
=========

`http.bash` is the minimalistic HTTP server mostly written in bash.

I tried to minimize external dependencies if possible.  Though, it has dependencies of `readlink(1)`, `dd(1)` and `cat(1)`.

Currently, it supports following HTTP requests; GET, HEAD, POST

If the Request-URI ends with `.cgi`, it is handled by the external program in CGI.

Note that `http.bash` exists for the demonstration of possibility of a bash script.  Don't expect it to have production quality as it may have many security holes.


Running
-------

You need either [`tcpserver`](http://cr.yp.to/ucspi-tcp/tcpserver.html) or [`nc`](http://nc110.sourceforge.net/) (a.k.a., netcat).

To support more than one connection, you'l need `tcpserver` rather than `nc`.  Note that some BSD version of `nc` is not supported.  (If `nc -h` does not shows `-e` option, your version is probably BSD one.)

    $ DOCUMENT_ROOT=/var/www/localhost/htdoc/
    $ tcpserver 0 8080 ./http.bash
    
    Or

    $ DOCUMENT_ROOT=/var/www/localhost/htdoc/
    $ while :; do nc -l -p 8080 -e ./http.bash; done

