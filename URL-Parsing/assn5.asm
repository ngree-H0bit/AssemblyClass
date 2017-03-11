; Pablo Breuer
; Library Functions for C Program
; March 5, 2017
;Assemble command: nasm -f elf32 assn5.asm
;
;Link command: ld -o assign5 -m elf_i386 -g lib4.o dns.o assn5.o
;Program  retrieves the content of the specified URL and save it to a
;file that is named after the last component of the URL. For example, if you
; are given the URL http://www.nps.edu/foo.html you would connect to
; www.nps.edu, send a request for /foo.html and save the returned content into
; a file named foo.html.
; For URL http://faculty.nps.edu/cseagle/cs4678/simple_client.c you would save
; the content into a file named simple_client.c. If the last component if the
; URL is missing (ie the last character is / as in http://www.nps.edu/ or not
; present as in http://www.nps.edu), then save the content into a file named
; index.html.

BITS 32

section .text

extern resolv
extern l_strlen
extern l_open
extern l_write
extern l_close
extern l_exit

struc sockaddr_in
    .sin_family:    resw  1
    .sin_port:      resw  1
    .sin_addr:      resd  1
    .sin_pad:       resb  8
endstruc

SOCK_STREAM equ 1
AF_INET equ 2
HTTP_PORT equ 80
SYS_SOCKETCALL equ 102
SYS_SOCKET equ 1
SYS_CONNECT equ 3
SYS_SEND equ 9
SYS_RECV equ 10
O_CREAT_WRONLY equ 65
O_CREAT_WRONLY_TRUN equ 577
S_READ_WRITE equ 384

global _start

_start:

  mov   ebx, [esp+8]      ;move to argv[1]
  add   ebx, 7            ;bypass http://
  push  ebx               ;push address of URL
  call  l_strlen          ;'cause code re-use :)
  add   esp, 4            ;clean up stack
  mov   ecx, eax;         ;move strlen of URL to ecx
  mov   [url_len], eax    ;save URL length

  mov   [p_url], ebx      ;pointer to the URL

findfirstslash:           ;find slash immediately after hostname, if any
  mov   al, '/'           ;looking for '/'
  cld                     ;clear flag, search forward
  mov   edi, [p_url]      ;pointer to the url
  repne scasb             ;starting at edi, go through memory until '/ found
                          ;when done, edi will contain url w/out hostname
  mov   [filepath_len], ecx ;filepath len = url - hostname
  mov   esi, [url_len]    ;esi contains url len including hostname

  jne   noslash           ;if no slash don't subtract, if slash, subtract 1
                          ;from the host_len
  sub   esi, 1            ;subtract 1 from host_len to account for '/'

noslash:
  sub   esi, [filepath_len] ;subtract filepath length to determine host length
  mov   [host_len], esi

  test  ecx, ecx            ;If ecx==0, no path was provided
  jz    nopath

  mov   [p_filepath], edi   ;edi points to filepath

findlastslash:
  mov   al, '/'             ;looking for '/'
  std                       ;set direction flag, move backward from the end
  add   edi, [filepath_len] ;move edi to the end of url
  repne scasb               ;edi should point to the last '\'
  test  ecx, ecx            ;if ecx==0, no '/'
  jz    onlyfilename

  add   edi, 2
  cmp byte [edi], 0x00      ;Does url end with /
  je    endswithslash

onlyfilename:
  mov   [p_filename], edi
  jmp   prep_resolv

nopath:
  mov dword [filepath_len], 0x00  ;There was no path, so sent length to 0

endswithslash:
  mov   edi, default_filename       ;No filename so set to index.html
  mov   [p_filename], edi

prep_resolv:
  sub   esp, [host_len]         ;make room on the stack
  sub   esp, 1                  ;make room for null terminator
  cld
  mov   edi, esp
  mov   esi, [p_url]
  mov   ecx, [host_len]
  rep movsb                     ;move hostname to stack for resolv
  mov byte [edi], 0x00          ;add null terminator

  push  esp                     ;push point to hostname
  call  resolv                  ;resolve hostname
  add   esp, 4                  ;clean up stack from resolv
  add   esp, [host_len]         ;clean up stack from hostname
  cmp   eax, -1                 ;check for error condition
  je    done                    ;can't resolve hostname so exit
  mov   [ip_addr], eax          ;save ip address returned from resolv

set_socket:
  push  dword 0
  push  dword SOCK_STREAM
  push  dword AF_INET
  mov   ecx, esp
  mov   ebx, SYS_SOCKET
  mov   eax, SYS_SOCKETCALL
  int   0x80
  add   esp, 12                 ;clean up stack
  cmp   eax, -1                 ;check for error condition
  je    done
  mov   [sockfd], eax             ;save socket

connect:
  mov   eax, [ip_addr]
  mov   [server + sockaddr_in.sin_addr], eax
  mov   word [server + sockaddr_in.sin_port], 0x5000     ;port 80
  mov   word [server + sockaddr_in.sin_family], AF_INET
  push  dword sockaddr_in_size
  push  server
  push  dword [sockfd]
  mov   ecx, esp
  mov   ebx, SYS_CONNECT
  mov   eax, SYS_SOCKETCALL
  int   0x80
  add   esp, 12                 ;cleanup stack
  cmp   eax, -1                 ;check for error condition
  je    done                    ;connection failed, close and exit
  je    closesocket

send:
  xor   ecx, ecx
  add   ecx, 45                 ;min packetlength
  add   ecx, [host_len]
  add   ecx, [filepath_len]
  sub   esp, ecx                ;make room on stack
  mov   [get_req_len], ecx      ;save the request length

  mov   edi, esp                ;prep GET string
  mov   esi, get
  mov   ecx, 5                  ;length of 'GET /'
  cld
  rep   movsb                     ;copy 'GET /' onto stack

  mov   ecx, [filepath_len]
  mov   esi, [p_filepath]
  rep   movsb                     ;move filepath onto stack

  mov   ecx, 17                 ;length of host string
  mov   esi, host               ; ` HTTP/1.0\r\nHost: `, 0x00
  rep   movsb

  mov   ecx, [host_len]
  mov   esi, [p_url]
  rep   movsb

  mov   ecx, 23                  ;length of connection string
  mov   esi, connection          ;`\r\nConnection: close\rn\rn`, 0x00 ;
  rep   movsb

  mov   ecx, esp                 ;save request string
  push  dword 0x00
  push  dword [get_req_len]
  push  ecx                      ;push request string
  push  dword [sockfd]
  mov   ecx, esp
  mov   ebx, SYS_SEND
  mov   eax, SYS_SOCKETCALL
  int   0x80
  add   esp, 16                   ;cleanup stack
  add   esp, [get_req_len]        ;cleanup stack
  cmp   eax, -1                   ;check for error condition
  je    closesocket               ;error on send, we're done

createfile:
  push  S_READ_WRITE
  push  O_CREAT_WRONLY
  push  dword [p_filename]
  call  l_open
  add   esp, 12                ;cleanup stack
  cmp   eax, 1                 ;check for error condition
  jz    closesocket            ;can't create file, we're done
  mov   [fd], eax              ;save fd

recv:
  push  0
  push  1500                   ;buffer size
  push  recv_buf
  push  dword [sockfd]
  mov   ecx, esp
  mov   ebx, SYS_RECV
  mov   eax, SYS_SOCKETCALL
  int   0x80
  add   esp, 16               ;cleanup stack
  cmp   eax, 0                ;check for no bytes received
  jle   closefile             ;if error/no bytes received, close file

writefile:
  push  eax                     ;push bytes from recv
  push  recv_buf                ;push buffer
  push  dword [fd]
  call  l_write
  add   esp, 12                 ;cleaup stack
  cmp   eax, -1                 ;check for error condition
  jle   closefile

  jmp   recv

closefile:
  push  dword [fd]
  call  l_close
  add   esp, 4                  ;stack cleanup

closesocket:
  push  dword [sockfd]
  call  l_close
  add   esp, 4                  ;stack cleanup

done:
  mov eax, 0
  call l_exit

section .data
get   db    `GET /`, 0x00   ;len 5 bytes
align 4
host  db    ` HTTP/1.0\r\nHost: `, 0x00 ;len 17 bytes
align 4
connection  db  `\r\nConnection: close\r\n\r\n`, 0x00 ;len 23 bytes
align 4
default_filename  db  'index.html', 0x00

section .bss
align 4
p_url resd  1
url_len resd 1
p_filepath resd 1
filepath_len resd 1
p_filename resd 1
host_len resd 1
ip_addr resd 1
fd resd 1
sockfd resd 1
get_req_len resd 1
align 4
server resb sockaddr_in_size
align 4
recv_buf resb 1500 ;max size
