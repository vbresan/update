; UPDATE.ASM	source datoteka programa koji vrsi refresh datoteka,
;		assemblirati sa NASMom.
;
;		U slucaju da poznajete nekakav nacin na koji bi kod bio
;		dodatno optimiziran, autor bi bio zahvalan kada bi o
;		toj mogucnosti optimizacije bio obavijesten.
;
;		U konfiguracijsku datoteku FROM.CFG upisati pathove
;		(s imenima) datoteka (medjusobno odvojene znakom za prelazak 
;		na pocetak novog reda) koje se kopiraju (wildcards vrijede 
;		samo za	imena datoteka).
;		U konfiguracijsku datoteku TO.CFG upisati (samo jedan) 
;		path u koji se vrsi refresh. Path mora zavrsavati
;               znakom '\' i znakom za prelazak na pocetak novog reda.
;               Program, obje konfiguracijske datoteke i datoteke ciji ce se 
;		refresh vrsiti moraju se nalaziti u istom direktoriju.
;		Program se mora pokretati iz direktorija u kojem se nalazi.
;               Maximalna velicina datoteke FROM.CFG iznosi 320B
;               Maximalna velicina datoteka TO.CFG iznosi 80B




 BITS 16				; NASM header za COM datoteku
 ORG 0X100
 
 SECTION .text
 
	mov	ah, 09h			; ispisi podatke o programu 
	mov	dx, screen		; na ekran
	int	21h
	
	call	HandleToFile
	
	mov	ax, 3D00h		; otvori 'from' datoteku
	mov	dx, from_file
	int	21h
	
	jnc	no_error2
	
	mov	ah, 09h
	mov	dx, msg_error2
	int	21h
	
	mov	ax, 4C02h
	int	21h
	
no_error2:
	mov	bx, ax
	mov	ah, 3Fh			; procitaj 320B iz 'from' datoteke
	mov	cx, 320
	mov	dx, fFrom
	int	21h
	
	mov	[num_B_read], ax	; cuvam broj procitanih B
	
	mov	ah, 3Eh			; zatvori 'from' datoteku
	int	21h			; bx nepromjenjen od proslog poziva

l10:
	mov	cx, [num_B_scan]
	mov	dx, [num_B_read]
	cmp	cx, dx
	jae	bye
	
	mov	si, fFrom
	add	si, [num_B_scan]
	mov	di, ext
l8:
	lodsb
	
	cmp	al, 13
	je	l9
	
	stosb
	inc	cx
	jmp	l8
l9:
	mov	al, 0
	stosb
	inc	cx
	inc	cx    			; preskoci 1B
	mov	[num_B_scan], cx
	
	mov	cl, [ext]		; ako ima jos bajtova, ali ne bitnih
	cmp	cl, 0
	je	bye
	
	mov	cx, 3Fh			; file mask - any file (findfirst)
	
	mov	dx, ext
	call	FindAllFromF
	
	jmp	l10
bye:	
	mov	ax, 4C00h		; izadji bez errora
	int	21h

;_____________________________________________________________________________
;
; HandleToFile

HandleToFile:
	mov	ax, 3D00h		; otvori 'to' datoteku
	mov	dx, to_file
	int	21h
	
	jnc	no_error1
	
	mov	ah, 09h
	mov	dx, msg_error1
	int	21h
	
	mov	ax, 4C01h
	int	21h
	
no_error1:
	mov	bx, ax
	mov	ah, 3Fh			; procitaj max 80B iz 'to' datoteke
	mov	cx, 80
	mov	dx, fTo
	int	21h
	
	mov	ah, 3Eh			; zatvori 'to' datoteku
	int	21h			; bx nepromjenjen od proslog poziva
	
	mov	si, fTo			; sredi ucitani path
	mov	di, fTo
	xor	cx, cx
l6:
	lodsb
	
	cmp	al, 13
	je	l7
	
	stosb
	inc	cx
	jmp	l6
l7:
	mov	al, 0
	stosb
	mov	[strlen_fTo], cx
	
	ret
;_____________________________________________________________________________
;
; FindAllFromF  Pronalazi sve datoteke zadane pathom i ekstenzijom na koje
;		pokazuje dx, u cx se nalaze atributi datoteka.
;
;		Nakon svakog findfirsta iz DTA	uzima filename i upisuje ga 
;		(ASCIZ) u fname. Poziva proceduru koja trazi istoimene dat.
;		na mjestu na kojem ce se vrsit backup.

FindAllFromF:
	mov	ah, 4Eh			; findfirst
	int	21h
	
	jc	_ret
	
l2:	mov 	si, 80h+1Eh		; ff.file_name --> fname
	mov	di, fname
l1:
	lodsb				;mov	al, [si] ;inc	si
	stosb				;mov	[di], al ;inc	di
	
	cmp	al, 0
	jne	l1
	
	mov	ah, 1Ah			; set new DTA
	mov	dx, ToDTA
	int	21h
	
	call FindCorrToF		; potrazi istoimenu datoteku u 
					; To direktoriju

	mov	ah, 1Ah			; set default DTA
	mov	dx, 80h
	int	21h

	mov	ah, 4Fh			; findnext			
	int	21h
	
	jnc	l2			; ako ima jos datoteka
_ret:	
	ret
;_____________________________________________________________________________
;
; FindCorrToF 	Provjerava postoji li datoteka naziva 'fname' u fTo pathu.
;		Ako ne postoji zove proc za kopiranje.
;		Ako postoji cita njen filedate i filetime. Ako su manji
;		od fd i ft orig datoteke fname zove proc za kopiranje.

FindCorrToF:
	mov	si, fname
	mov	di, fTo
	add	di, [strlen_fTo]
l3:	
	lodsb
	stosb
	
	cmp	al, 0
	jne	l3
	
	mov	cx, 3Fh			; findfirst
	mov	dx, fTo
	mov	ah, 4Eh			
	int	21h
	
	jc	call_FCAndP
	
	mov	ax, [80h+18h]		; cmp date
	mov	bx, [ToDTA+18h]

	cmp	ax, bx
	jb	call_ret
	
	cmp	ax, bx
	ja	call_FCAndP
					
	mov	ax, [80h+16h]		; cmp time
	mov	bx, [ToDTA+16h]
	
	cmp	ax, bx
	jbe	call_ret
	
call_FCAndP:
	call	FCopy
	call	FPrint
call_ret:	
	ret
;_____________________________________________________________________________
;
; FCopy		Kopira datoteku 'fname' u 'fTo'
;

FCopy:
	mov	ax, 3D00h		; otvori 'fname' za citanje
	mov	dx, fname
	int	21h
	
	jnc	no_error3
	
	mov	ah, 09h
	mov	dx, msg_error3
	int	21h
	
	mov	ax, 4C03h
	int	21h
	
no_error3:
	mov	[fH_in], ax
	
	mov	ah, 3Ch			; stvori 'fTo' za pisanje
	xor	cx, cx			;mov cx, 0
	mov	dx, fTo
	int	21h
	
	jnc	no_error4
	
	mov	ah, 09h
	mov	dx, msg_error4
	int	21h
	
	mov	ax, 4C04h
	int	21h
	
no_error4:
	mov	[fH_out], ax
				
	mov	cx, 0FFFFh
	mov	dx, in_buffer
copy_block:	
	mov	bx, [fH_in]
	mov	ah, 3Fh			; procitaj blok
	int	21h
	
	cmp	ax, 0
	je	__ret
	
	mov	bx, [fH_out]
	mov	cx, ax
	mov	ah, 40h			; upisi blok
	int	21h
	
	jmp	copy_block
__ret:		
	mov	ah, 3Eh			; zatvori datoteku za pisanje
;	mov	bx, [fH_in]		; vec je u bx-u
	int	21h
	
	mov	ah, 3Eh			; zatvori datoteku za citanje
	mov	bx, [fH_out]
	int	21h
	
	call	ModDate
	
	ret
;_____________________________________________________________________________
;
; ModDate	Mijenja date i time kreirne datoteke u onaj kojeg
;		posjeduje datoteka koja se 'kopira'
;

ModDate:
	mov	ax, 3D00h			; otvori 'fTo' za citanje
	xor	cx, cx
	mov	dx, fTo
	int	21h
	
	mov	bx, ax
	
	mov	ax, 5701h		; postavi datoteci (za pisanje) datum ...
	mov	cx, [80h+16h]		; ... i vrijeme kojeg ima datoteka za ...
	mov	dx, [80h+18h]		; ... citanje
	int	21h
	
	mov	ah, 3Eh
	int	21h
	
	ret
;_____________________________________________________________________________
;
; FPrint	Ispisuje file_name, file_date i file_time kopirane datoteke
;

FPrint:
	call	Print13chFName
	
;	mov	al, " "			; ostali nepromjenjeni iz ...
;	mov	ah, 0Eh			; ... Print13chFName
;	xor	bh, bh
	int	10h

	call	PrintFDate
	
	mov	al, " "
;	mov	ah, 0Eh			; ostali nepromjenjeni iz ...
;	xor	bh, bh			; ... PrintFDate->Print2dgNum
	int	10h
	
	call	PrintFTime
	
	mov	al, 10			; print chars CR, LF
;	mov	ah, 0Eh			; ostali nepromjenjeni iz ...
;	xor	bh, bh			; ... PrintFTime->Print2dgNum
	int	10h
	
	mov	al, 13
;	mov	ah, 0Eh			; ostali nepromjenjeni od proslog ...
;	xor	bh, bh			; ... poziva interrupta
	int	10h
	
	ret
;_____________________________________________________________________________
;
; Print13chFName	Ispisuje (i mijenja u $-terminated) ASCIZ ime 
;			datoteke (fname) dugo 13 znakova, s desne strane 
;			dopunjeno spaceovima

Print13chFName:
	xor	bx, bx
	mov 	si, fname
	mov	di, fname
l4:
	lodsb
	
	cmp	al, 0
	je	l5
	
	stosb
	
	inc	bx
	jmp	l4
l5:
	mov	al, "$"
	stosb
	
	mov	ah, 09h
	mov	dx, fname
	int	21h
	
	mov	cx, 12
	sub	cx, bx
	
	mov	ah, 0Eh
	mov	al, " "
	xor	bh, bh
	
	cmp	cx, 0
	je	skip_space
space:
	int	10h
	loop	space
skip_space:	
	ret
;_____________________________________________________________________________
;
; PrintFDate	Iz DTA cita filedate i ispisuje ga na ekran

PrintFDate:
	mov	ax, [80h+18h]		; dani		
     	and	ax, 001Fh	
	call	Print2dgNum
	
	mov	al, "."
;	mov	ah, 0Eh			; ostali nepromjenjeni iz Print2dgNum			
;	xor	bh, bh
	int	10h
	
	mov	ax, [80h+18h]		; mjeseci
     	and	ax, 01E0h
	shr	ax, 5
	call 	Print2dgNum
	
	mov	al, "."
;	mov	ah, 0Eh			; ostali nepromjenjeni iz Print2dgNum
;	xor	bh, bh
	int	10h
	
	mov	ax, [80h+18h]		; godine
     	and	ax, 0FE00h
	shr	ax, 9
	add	ax, 1980
	
	xor	dx, dx
	mov	bx, 1000
	div	bx
	
	add	al, 30h			; 30h - dodajem ascii razliku
	mov	ah, 0Eh
	xor	bh, bh
	int 	10h
	
	mov	ax, dx
	mov	bl, 100
	div	bl
	
	mov	cl, ah
	
	add	al, 30h
	mov	ah, 0Eh
;	xor	bh, bh			; ostao nepromjenjen od proslog ...  
	int 	10h			; ... poziva interrupta
	
	xor	ah, ah
	mov	al, cl
	call	Print2dgNum
	
	ret
;_____________________________________________________________________________
;
; PrintFTime	Iz DTA cita filetime i ispisuje ga na ekran (osim sekunda)

PrintFTime:
	mov	ax, [80h+16h]		; sati
	and	ax, 0F800h
	shr	ax, 11
	
	call	Print2dgNum
	
	mov	al, ":"
;	mov	ah, 0Eh			; ostali nepromjenjeni iz Print2dgNum
;	xor	bh, bh
	int	10h
	
	mov	ax, [80h+16h]		; minute
	and	ax, 07E0h
	shr	ax, 5
	
	call	Print2dgNum
	
	ret
;_____________________________________________________________________________
;
; Print2chNum	Ispisuje dvoznamenkasti broj iz al na ekran

Print2dgNum:
	mov	bl, 10
	div	bl
	add	al, 30h			; 30h - dodajem ascii razliku
	
	mov	cl, ah
	add	cl, 30h			; 30h - dodajem ascii razliku
	
	mov	ah, 0Eh
	xor	bh, bh
	int 	10h
	
	mov	al, cl
;	mov	ah, 0Eh			; ostali nepromjenjeni od proslog ...
;	xor	bh, bh			; ... poziva interrupta
	int 	10h
	
	ret
;_____________________________________________________________________________
 
 SECTION .data
 
	screen		db	10,13,"Update v0.3 by                1999",10,13,10,"$"
		
	strlen_fTo	db	0
	
	to_file		db	"to.cfg",0
	msg_error1	db	"Error1: can't open file TO.CFG!",10,13,10,"$"
	
	from_file	db	"from.cfg",0
	msg_error2	db	"Error2: can't open file FROM.CFG!",10,13,10,"$"
	
	msg_error3	db	"Error3: can't open input file!",10,13,10,"$"
	msg_error4	db	"Error4: can't open output file!",10,13,10,"$"
	
	fH_in		dw	0
	fH_out		dw	0
	
	num_B_read	dw	0
	num_B_scan	dw	0

 SECTION .bss
 
 	fname	        resb	13
	ToDTA		resb	49
	
	fTo		resb	82
	fFrom		resb	320
	
	ext		resb	82
	
	in_buffer	resb	65536