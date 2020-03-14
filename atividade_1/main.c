#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "buffer.h"

/// Reserva uma região de memória capaz de guardar capacity ints e
/// inicializa os atributos de b
void init_buffer(buffer_t* b, int capacity0) {
    b->capacity = capacity0;
    b->size = 0;
}

/// Libera a memória e quaisquer recursos de propriedade de b. Desfaz o
/// init_buffer()
void destroy_buffer(buffer_t* b) {
}

/// Retorna o valor do elemento mais antigo do buffer b, ou retorna -1 se o
/// buffer estiver vazio
int take_buffer(buffer_t* b) {
    return 0;
}

/// Adiciona um elemento ao buffer e retorna 0, ou retorna -1 sem
/// alterar o buffer se não houver espaço livre
int put_buffer(buffer_t* b, int val) {
    b->size++;
    return 0;
}

/// Lê um comando do terminal e o executa. Retorna 1 se o comando era
/// um comando normal. No caso do comando de terminar o programa,
/// retorna 0
int ler_comando(buffer_t* b){
    char op;
    int num;

    while (1)
    {
        printf("Comandos:\nr: retirar\nc: colocar\nq: sair\n");
        scanf("%c\n",&op);

        if(op=='q'){
            break;
        } else if (op=='r'){
            take_buffer(b);
            return 1;
        } else if (op=='c'){

            printf("%d\n",b->size);
            scanf("%d\n",&num);

            put_buffer(b,num);
            printf("%d\n",b->size);
            return 1;

        } else {
            return 0;
        }
    }
    return 1;
}

int main(int argc, char **argv) {

    int capacity = 0;
    printf("Digite o tamanho do buffer:\n>");
    if (scanf("%d", &capacity) <= 0) {
        printf("Esperava um número\n");
        return 1;
    }
    buffer_t b;

    init_buffer(&b, capacity);

    ler_comando(&b);
    
    //////////////////////////////////////////////////
    // Chamar ler_comando() até a função retornar 0 //
    //////////////////////////////////////////////////

    // *** ME COMPLETE ***

    destroy_buffer(&b);
    return 0;
}
