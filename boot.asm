[BITS 16]                       ; Indique à NASM de générer du code 16 bits par défaut
org 0x7C00                      ; Dit au lieur que le code sera chargé à l'adresse mémoire 0x7C00

start:                          ; Point d'entrée principal du bootloader
    xor ax, ax                  ; Met le registre AX à 0 en faisant un XOR sur lui-même
    mov ds, ax                  ; Initialise le segment de données (DS) à 0x0000
    mov es, ax                  ; Initialise le segment supplémentaire (ES) à 0x0000
    mov ss, ax                  ; Initialise le segment de pile (SS) à 0x0000
    mov sp, 0x7C00              ; Place le pointeur de pile (SP) juste avant le bootloader (sécurisé)

    mov si, msg                 ; Charge l'adresse mémoire du message de départ dans le registre SI
print:                          ; Boucle d'affichage du texte en 16 bits
    lodsb                       ; Charge le caractère pointé par SI dans AL, puis incrémente SI
    cmp al, 0                   ; Vérifie si le caractère est un zéro de fin de chaîne (caractère nul)
    je switch_to_32bit          ; Si AL vaut 0, le message est fini, on saute vers la transition 32 bits
    mov ah, 0x0E                ; Configure la fonction d'affichage de caractère du BIOS (Teletype)
    int 0x10                    ; Appelle l'interruption vidéo du BIOS pour afficher le caractère dans AL
    jmp print                   ; Recommence la boucle pour le caractère suivant

msg: db 'Bonjour tout le monde !', 13, 10, 0 ; Stocke la chaîne avec retour chariot (13), fin de ligne (10) et zéro (0)

switch_to_32bit:                ; Section de transition vers le mode protégé
    cli                         ; Désactive les interruptions matérielles (le BIOS ne fonctionnera plus)
    lgdt [gdt_descriptor]       ; Charge la structure de la GDT dans le registre GDTR du processeur

    mov eax, cr0                ; Copie le registre de contrôle CR0 dans EAX pour le modifier
    or eax, 0x1                 ; Passe le bit 0 (Protected Mode Enable) à 1 dans EAX
    mov cr0, eax                ; Renvoie la valeur modifiée dans CR0, activant le mode protégé au niveau matériel

    jmp CODE_SEG:init_pm        ; Effectue un "Far Jump" (saut lointain) pour appliquer le segment de code et vider le pipeline

[BITS 32]                       ; Indique à NASM de générer du code 32 bits à partir d'ici
init_pm:                        ; Point d'entrée officiel en mode protégé 32 bits
    mov ax, DATA_SEG            ; Charge l'offset du segment de données de la GDT dans AX
    mov ds, ax                  ; Met à jour le segment de données (DS) avec le sélecteur 32 bits
    mov ss, ax                  ; Met à jour le segment de pile (SS) avec le sélecteur 32 bits
    mov es, ax                  ; Met à jour le segment supplémentaire (ES) avec le sélecteur 32 bits
    mov fs, ax                  ; Met à jour le segment FS avec le sélecteur 32 bits
    mov gs, ax                  ; Met à jour le segment GS avec le sélecteur 32 bits

    mov ebp, 0x90000            ; Configure la base de la pile 32 bits à une adresse mémoire haute et sûre
    mov esp, ebp                ; Initialise le pointeur de pile actuel (ESP) sur la base de la pile

    ; --- EFFACEMENT DE L'ÉCRAN EN MODE PROTÉGÉ ---
    mov edi, 0xB8000            ; Charge l'adresse de début de la mémoire vidéo VGA
    mov ecx, 2000               ; Un écran standard fait 80x25 = 2000 caractères à effacer
clear_screen_loop:              ; Boucle pour nettoyer l'écran textuel
    mov byte [edi], ' '         ; Écrit un caractère espace pour effacer ce qui existe
    inc edi                     ; Avance d'un octet pour pointer sur l'attribut de couleur
    mov byte [edi], 0x07        ; Met la couleur par défaut (Gris clair sur fond noir)
    inc edi                     ; Avance d'un octet pour passer au caractère suivant
    loop clear_screen_loop      ; Décrémente ECX et re-boucle tant que ECX n'est pas à 0

    ; --- AFFICHAGE DU MESSAGE DE SUCCÈS ---
    mov esi, msg_success        ; Charge l'adresse du message de succès dans ESI
    mov edi, 0xB8000            ; Réinitialise EDI au début de la mémoire vidéo (en haut à gauche)

print_string_32:                ; Boucle d'affichage direct dans la mémoire vidéo en 32 bits
    lodsb                       ; Charge le caractère pointé par ESI dans AL, puis incrémente ESI
    cmp al, 0                   ; Vérifie si on a atteint la fin du message (caractère nul)
    je end_loop                 ; Si oui, on quitte la boucle d'affichage
    mov [edi], al               ; Écrit le code ASCII du caractère directement dans la mémoire vidéo
    inc edi                     ; Avance le pointeur de la mémoire vidéo d'un octet (position de la couleur)
    mov byte [edi], 0x0E        ; Écrit l'attribut de couleur (0x0E = Jaune sur fond noir)
    inc edi                     ; Avance le pointeur vidéo d'un octet pour pointer sur le caractère suivant
    jmp print_string_32         ; Recommence pour le caractère suivant

end_loop:                       ; Boucle de fin pour empêcher le processeur de faire n'importe quoi
    hlt                         ; Met le processeur en état de veille (Halt) en attendant une interruption
    jmp end_loop                ; Sécurité absolue : si le CPU se réveille, on le rebloque en boucle

; Définition du message avec encodage manuel des accents pour la table VGA standard
msg_success:
    db "Le passage au mode prot", 0x82, "g", 0x82, " (32 bits) a march", 0x82, " avec succ", 0x8A, "s !", 0

align 4                         ; Aligne la GDT sur une frontière de 4 octets pour optimiser la lecture CPU
gdt_start:                      ; Marqueur de début de la Global Descriptor Table (GDT)

gdt_null:                       ; Descripteur nul obligatoire (Entrée 0 de la GDT)
    dd 0x00000000               ; Définit les 4 premiers octets à zéro
    dd 0x00000000               ; Définit les 4 derniers octets à zéro (total de 8 octets)

gdt_code:                       ; Descripteur de segment de code (Entrée 1 de la GDT)
    dw 0xFFFF                   ; Limite du segment (bits 0 à 15) : Taille maximale
    dw 0x0000                   ; Base du segment (bits 0 à 15) : Commence à l'adresse 0x0
    db 0x00                     ; Base du segment (bits 16 à 23)
    db 10011010b                ; Octet d'accès : Présent, Privilège 0 (Kernel), Code, Exécutable, Lecture seule
    db 11001111b                ; Drapeaux (Granularité 4Ko, Mode 32 bits) + Limite du segment (bits 16 à 19)
    db 0x00                     ; Base du segment (bits 24 à 31)

gdt_data:                       ; Descripteur de segment de données (Entrée 2 de la GDT)
    dw 0xFFFF                   ; Limite du segment (bits 0 à 15) : Taille maximale
    dw 0x0000                   ; Base du segment (bits 0 à 15) : Commence à l'adresse 0x0
    db 0x00                     ; Base du segment (bits 16 à 23)
    db 10010010b                ; Octet d'accès : Présent, Privilège 0 (Kernel), Données, Lecture et Écriture autorisées
    db 11001111b                ; Drapeaux (Granularité 4Ko, Mode 32 bits) + Limite du segment (bits 16 à 19)
    db 0x00                     ; Base du segment (bits 24 à 31)

gdt_end:                        ; Marqueur de fin de la GDT permettant de calculer sa taille dynamique

gdt_descriptor:                 ; Structure transmise à l'instruction 'lgdt'
    dw gdt_end - gdt_start - 1  ; Spécifie la taille réelle de la table en octets moins 1
    dd gdt_start                ; Spécifie l'adresse mémoire exacte du début de la GDT

CODE_SEG equ gdt_code - gdt_start ; Calcule la position du segment de code dans la GDT (Vaut 0x08)
DATA_SEG equ gdt_data - gdt_start ; Calcule la position du segment de données dans la GDT (Vaut 0x10)

times 510 - ($ - $$) db 0       ; Remplit le reste du secteur (jusqu'à l'octet 510) avec des zéros
dw 0xAA55                       ; Écrit la signature de boot magique obligatoire sur les deux derniers octets
