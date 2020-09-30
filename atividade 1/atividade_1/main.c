#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "buffer.h"

/// Reserva uma região de memória capaz de guardar capacity ints e
/// inicializa os atributos de b
void init_buffer(buffer_t* b, int capacity0) {
    b->capacity = capacity0;
    b->size = 0;
    b->put_idx = 0;
    b->take_idx = 0;
    b->data = (int*) malloc(capacity0 * sizeof(int));

}

/// Libera a memória e quaisquer recursos de propriedade de b. Desfaz o
/// init_buffer()
void destroy_buffer(buffer_t* b) {
    free(b->data);
}

/// Retorna o valor do elemento mais antigo do buffer b, ou retorna -1 se o
/// buffer estiver vazio
int take_buffer(buffer_t* b) {
    int num;
    if(b->size > 0){
        num = b->data[b->take_idx];
        b->data[b->take_idx] = -2;
        b->take_idx++;
        b->size--;
        if (b->take_idx >= b->capacity){
            b->take_idx = 0;
        }
    } else {
        return -1;
    }
    return num;
}

/// Adiciona um elemento ao buffer e retorna 0, ou retorna -1 sem
/// alterar o buffer se não houver espaço livre
int put_buffer(buffer_t* b, int val) {
    if(b->size < b->capacity){
        b->data[b->put_idx] = val;
        b->size++;
        b->put_idx++;
        if(b->put_idx >= b->capacity){
            b->put_idx = 0;
        }

    } else {
        return -1;
    }

    return 0;
}

/// Lê um comando do terminal e o executa. Retorna 1 se o comando era
/// um comando normal. No caso do comando de terminar o programa,
/// retorna 0
int ler_comando(buffer_t* b);

int main(int argc, char **argv) {

    int capacity = 0;
    printf("Digite o tamanho do buffer:\n>");
    if (scanf("%d", &capacity) <= 0) {
        printf("Esperava um número\n");
        return 1;
    }
    buffer_t b;

    init_buffer(&b, capacity);

    printf("Comandos:\n"
           "r: retirar\n"
           "c: colocar\n"
           "q: sair\n\n");

    while(ler_comando(&b));

    //////////////////////////////////////////////////
    // Chamar ler_comando() até a função retornar 0 //
    //////////////////////////////////////////////////

    // *** ME COMPLETE ***

    destroy_buffer(&b);
    return 0;
}
