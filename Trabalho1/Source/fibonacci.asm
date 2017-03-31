.text
.globl main


.data
fib_value: .word 0:19
size: .word 19

main:
	la  $s0,fib_value  #Carrega endereço do vetor vazio
	la  $s1, size 	   #Carrega endereço do tamanho do vetor
	lw  $s2, 0($s1)    #Carrega o tamanho do vetor 
	addi $t0,$t0,0	   #Inicializa o primeiro valor da sequência: 0
	addi $t1,$t1,1	   #Inicializa o segundo valor da sequência: 1
	addi $t3,$t3,0 	   #Inicializa o indice que vai ser usado pra controle
	sw   $t0,0($s0)    #Inclui o primeiro valor do vetor no mesmo
	sw   $t1,4($s0)    #Inclui o segundo valor do vetor no mesmo
	
loop:	beq $t3,$s2,fim	   #Verifica se o indice de controle é igual ao tamanho do vetor
	lw $t0,0($s0)	   #Carrega valor n-2 
	lw $t1,4($s1)	   #Carrega o valor n-1
	add $t2,$t0,$t1    #Executa a soma dos dois valores
	sw $t2,8($s0)	   #Coloca o resultado da soma no vetor
	addi $s0,$s0,4	   #Incrementa a posição do vetor
	addi $t3,$t3,1	   #Incrementa indice de controle
	j loop

fim:
	li $v0,10
	syscall
	 
	
