; Pablo Breuer
; Library Functions for C Program
; February 15, 2017
;Assemble command: nasm -f elf32 start.asm
;		               nasm -f elf32 lib4.asm
;Link command: gcc -o main -m32 main.c lib4.o start.o -nostdlib \
; -nodefaultlibs -fno-builtin -nostartfiles

SYS_EXIT equ 1
SYS_READ equ 3
SYS_WRITE equ 4
SYS_OPEN  equ 5
SYS_CLOSE equ 6

STDIN equ 0
STDOUT equ 1

global l_strlen
global l_strcmp
global l_gets
global l_puts
global l_write
global l_open
global l_close
global l_exit

;int l_strlen(char *str);
;   return the length of the null terminated string, str. The null
;   character should not be counted.
l_strlen:
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  edi             ;must preserve edi per cdecl convention

      mov   ecx, 0xffffffff ;Set ecx to max value
      xor   al, al          ;clear lower have of eax
      cld                   ;clear the direction flags
      mov   edi, [ebp+0x08] ;Load edi with p_string
      repne scasb           ;Increment through edi looking for NULL,
                            ;decrement ecx as we go through string
      not ecx
      sub ecx, 1            ;Subtract 1 to because repne will count NULL
      mov eax, ecx          ;Put count into our return

      pop edi               ;Restore edi per cdecl

      mov   esp, ebp        ;Normal function epilogue
      pop   ebp
      ret

;int l_strcmp(char *str1, char *str2);
;   return 0 isf str1 and str2 are equal, return 1 if they are not.
;   Note that this is not the same definition as the C standard library
;   function strcmp.
l_strcmp:
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  ebx		    ;Save ebx per cdecl
      push  esi             ;Save esi per cdecl
      push  edi             ;Save edi per cdecl

      push  dword [ebp+0xc]  ;p_str2
      call  l_strlen
      add   esp, 4            ;caller cleans up stack -> arg
      mov   ebx, eax          ;ecx = strlen

      push  dword [ebp+0x08] ;p_str1
      call  l_strlen
      add   esp, 4            ;caller cleans up stack -> argc
      cmp   eax, ebx          ;compare string lengths
      jne   .not_equal        ;string lengths are not equal (short circuit)

      mov   esi, [ebp+0x08]   ;equal lengths so now must do byte comparison
      mov   edi, [ebp+0x0c]
      cld
      repe cmpsb
      test ecx, ecx
      jnz  .not_equal

.equal:                       ;strings equal
      mov  eax, 0
      jmp .done

.not_equal:                   ;strings not equal
      mov   eax, 1

.done:
      pop   edi             ;Restore edi per cdecl
      pop   esi             ;Restore esi
      pop   ebx             ;Restore ebx
      mov   esp, ebp        ;Normal function epilogue
      pop   ebp
      ret

;int l_gets(int fd, char *buf, int len);
;   read at most len bytes from file fd, placing them into buffer buf.
;   Terminate early if a new line character ('\n', 0x0A) characters is read.
;   If a new line character is encountered, it should be stored into the
;   output buffer and counted in the total number of bytes read.
;   Return the total number of bytes read (which may be zero if end of file
;   is reached or an error occurs). This function does not place a null
;   termination character after the last character read. That is the
;   responsibility of the caller.
l_gets:
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  ebx             ;Save ebx per cdecl

      sub   esp, 4          ;Make room for local counter

      cmp   dword [ebp+0x10], 0   ;If length is 0, we're done
      mov   eax,0
      je    .done

      mov   dword [esp], 0  ;set local counter to 0
      mov   ebx, [ebp+0x08] ;fd
      mov   ecx, [ebp+0x0c] ;p_buff
      mov   edx, 1

.loop_top:
      mov   eax, SYS_READ
      int   0x80

      cmp   eax, 1          ;Did we read a characters
      jne   .done           ;Error condition

      inc   dword [esp]     ;Increment our counter

      cmp   byte [ecx],0x0a  ;Did we read a carriage return
      je    .done

      inc   ecx             ;Increment buffer pointer

      mov   eax, [ebp+0x10] ;Move max_len into eax
      cmp   eax, [esp]        ;Does max_len equal counter?
      je    .done

      jmp   .loop_top

.done:

      mov   eax, [esp]
      add   esp, 4          ;de-allocate our counter
      pop   ebx             ;Restore ebx per cdecl

      mov   esp, ebp        ;Normal function epilogue
      pop   ebp
      ret

;void l_puts(const char *buf);
;   write the contents of the null terminated string buf to stdout.
;   The null byte must not be written. If the length of the string is
;   zero, then no bytes are to be written.
l_puts:                     
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  ebx             ;Save ebx per cdecl


       push  dword [ebp+0x08]  ;p_buff
       call  l_strlen         ;need to get size of string
       add   esp, 4
       push  eax	      ;push len
       push dword [ebp+0x08]        ;p_buff
       push STDOUT
       call l_write
       add  esp, 12

;      mov   ecx, eax
;      add   esp, 4           ;caller cleans up stack -> pushed arg
;      mov   eax, SYS_WRITE
;      mov   ebx, STDOUT

      pop   ebx             ;Restore ebx per cdecl

      mov   esp, ebp        ;Normal function epilogue
      pop   ebp
      ret

;int l_write(int fd, char *buf, int len);
;   write len bytes from buffer buf to file fd. Return the number of bytes
;   actually written or -1 if an error occurs.
l_write:
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  ebx             ;Save ebx per cdecl

      mov   eax, SYS_WRITE
      mov   ebx, [ebp+0x08] ;fd
      mov   ecx, [ebp+0x0c] ;p_buff
      mov   edx,  [ebp+0x10];len
      int 0x80

      pop   ebx             ;Restore ebx per cdecl

      mov   esp, ebp        ;Normal function epilogue
      pop   ebp
      ret

;int l_open(const char *name, int flags, int mode);
;   opens the named file with the supplied flags and mode. Returns the
;   integer file descriptor of the newly opened file or -1 if the file
;   can't be opened.
l_open:
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  ebx             ;Save ebx per cdecl

      mov   eax, SYS_OPEN
      mov   ebx, [ebp+0x08] ;p_filename
      mov   ecx, [ebp+0x0c] ;flags
      mov   edx, [ebp+0x10] ;mode
      int   0x80

      cmp   eax, 0          ;Did open succeed
      jge   .done           ;Open succeeded

      mov   eax, -1         ;Return error condition

.done:
      pop   ebx             ;Restore ebx per cdecl

      mov   esp, ebp        ;Normal function epilogue
      pop   ebp
      ret

;int l_close(int fd);
;   close the indicated file, returns 0 on success or -1 on failure.
l_close:
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  ebx             ;Save ebx per cdecl

      mov   eax, SYS_CLOSE
      mov   ebx,[ebp+0x08]  ;fd
      int   0x80            ;syscall

      pop   ebx             ;Restore ebx per cdecl

      mov   esp, ebp        ;Normal function epilogue
      pop   ebp
      ret

;int l_exit(int rc);
;   terminate the calling program with exit code rc.
;   Since all of these functions will be call
l_exit:
      push  ebp             ;Normal function prologue
      mov   ebp, esp

      push  ebx             ;Save ebx per cdecl

      mov   eax, SYS_EXIT
      mov   ebx, [ebp+0x08] ;Exit code
      int   0x80
