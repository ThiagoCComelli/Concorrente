#include <stdio.h>
#include <semaphore.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include "banco.h"
// #include "helper.c"
// 
// Faz uma transferência de valor unidades monetárias da conta origem
// para a conta destino. Se a conta origem tiver saldo insuficiente, o
// saldo fica negativo, simbolizando cheque especial.  
// 
// Essa função é "unsafe": ela não aplica nenhum mecanismo de
// sincronização e pode produzir valores errados se utilizada
// concorrentemente com a mesma conta.
//
// Definida em helper.c
extern void transferir_unsafe(conta_t *origem, conta_t *destino, double valor);

void transferir(conta_t *origem, conta_t *destino, double valor);

// Thread que faz  transferências aleatórias. Definida em helper.c
void* caixa_func(void *arg);

sem_t sem_lista;

// Versão thread-safe da função transferir_unsafe.
void transferir(conta_t *origem, conta_t *destino, double valor) {
    sem_wait(&sem_lista);

    pthread_mutex_lock(&origem->mutex);
    pthread_mutex_lock(&destino->mutex);

    // printf("\n\n");
    // printf("%2f\n",origem->saldo);
    // printf("%2f\n",destino->saldo);

    transferir_unsafe(origem, destino, valor);

    // printf("%2f\n",origem->saldo);
    // printf("%2f\n",destino->saldo);

    pthread_mutex_unlock(&destino->mutex);
    pthread_mutex_unlock(&origem->mutex);

    sem_post(&sem_lista);
}

int main(int argc, char* argv[]) {
    // Cria as contas com algum saldo e inicializa o mutex de cada conta
    for (int i = 0; i < NUM_CONTAS; i++) {
        contas[i].id = i;
        contas[i].saldo = 1000.00;
        pthread_mutex_init(&contas[i].mutex, NULL);
    }
  
    // Cria as threads
    pthread_t caixas[NUM_CAIXAS];
    sem_init(&sem_lista, 0, 1);

    for (int i = 0; i < NUM_CAIXAS; i++)
        pthread_create(&caixas[i], NULL, caixa_func, NULL);
  
    // Esperar as threads terminarem
    for (int i = 0; i < NUM_CAIXAS; i++)
        pthread_join(caixas[i], NULL);
  
    // Destroi os mutexes
    for (int i = 0; i < NUM_CONTAS; i++)
        pthread_mutex_destroy(&contas[i].mutex);

    sem_destroy(&sem_lista);
  
    return 0;
}
