.text
.globl main

main:   la $t0, Vetor #carrega vetor para t0
	
	ori $t2, $zero, 0 #index
	add $t3, $zero, 3 #cosntante

loop:	beq $t2, 5, fim #testa fim do loop
	lw $t4, 0($t0) #carrega proximo elemento do vetor
	add $t5, $t4, $t3 #t5 = t4 + t3
	sw $t5, 0($t0) #armazena resultado na respectiva posicao do vetor
	addiu $t2, $t2, 1 #incrementa 
	addiu $t0, $t0, 4 #aponta para a proxima posicao do vetor
	j loop #volta para o laço
fim: 	
	li $v0, 10 #finaliza o programa
	syscall #finaliza o programa

.data
Vetor: .word 2 5 12 3 4 #vetor de 5 posicoes
