#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <semaphore.h>
#include "types.h"

TicketCaller* pc;
pthread_mutex_t clientMutex;
pthread_mutex_t clerkMutex;
pthread_mutex_t clientWaitMutex;
sem_t semClerk;
sem_t semClient;
sem_t semClientWaitToCall;
sem_t semClerkWaitToClient;
cookerOrdersReady_t balcao;
cookerOrders_t cookerOrders;

void balcao_init(cookerOrdersReady_t* b){
	b->data = (order_t*) malloc(numClients * sizeof(order_t));
	b->actualSize = 0;
}

void cookerOrders_init(cookerOrders_t* b){
	b->data = (order_t*) malloc(numClients * sizeof(order_t));
	b->actualSize = 0;
}

void client_inform_order(order_t* od, int clerk_id) {
	pc->clerks_order_spot[clerk_id] = od;
	for (int i = 0; i < numClerks; i++)
	{
		sem_post(&semClerkWaitToClient);
	}
	
}

void client_think_order() {
	sleep(rand() % (clientMaxThinkSec + CLIENT_MIN_THINK_SEC) + CLIENT_MIN_THINK_SEC);
}

void client_wait_order(order_t* od) {
	pthread_mutex_lock(&clientWaitMutex);
	pc->clientsWaitingOrder++;
	pthread_mutex_unlock(&clientWaitMutex);

	while (1)
	{
		sem_wait(&semClient);
		for (int i = 0; i < balcao.actualSize; i++)
		{	
			if(balcao.data[i].password_num == od->password_num){
				pthread_mutex_lock(&clientWaitMutex);
				pc->clientsWaitingOrder--;
				pthread_mutex_unlock(&clientWaitMutex);

				pthread_exit(NULL);
			}				
		}
	}
}

void clerk_create_order(order_t* od) {
	cookerOrders.data[cookerOrders.actualSize] = *od; 
	cookerOrders.actualSize++;
}

void clerk_annotate_order() {
	sleep(rand() % (clerkMaxWaitSec + CLERK_MIN_WAIT_SEC) + CLERK_MIN_WAIT_SEC);
}

void cooker_wait_cook_time() {
	sleep(rand() % (cookMaxWaitSec + COOK_MIN_WAIT_SEC) + COOK_MIN_WAIT_SEC);
}

void* client(void *args) {
	client_t* cl = malloc(sizeof(int));
	cl->id = (long)args;

	int lastCheck = -1;

	// MUTEX PARA GARANTIR QUE VALORES NAO IRAO SE REPETIR 
	pthread_mutex_lock(&clientMutex);

	int pw = get_unique_ticket(pc);
	
	// GARANTE QUE O FUNCIONARIO SÓ COMECE A TRABALHAR APOS O PRIMEIRO CLIENTE PEGUE A PRIMEIRA SENHA
	sem_post(&semClerk);

	pthread_mutex_unlock(&clientMutex);

	// AGUARDA A LIBERACAO DO FUNCIONARIO APOS A CHAMADA SER EFETUADA
	sem_wait(&semClientWaitToCall);

	while (true)
	{
		// CONFICIONAL NECESSARIO PARA QUE A VERIFICACAO SO SEJA FEITA SE A LISTA MUDAR
		if(lastCheck < pc->lastCheckPwd){
			int *nums = show_current_tickets(pc);
			lastCheck = pc->lastCheckPwd;

			for(int i = 0; i<numClerks; i++){
				if(nums[i] == pw){
					client_think_order();

					order_t order;

					order.client_id = cl->id;
					order.password_num = pw;

					client_inform_order(&order,i);

					client_wait_order(&order);
				}
			}
		}
	}	
	return NULL;
}

void* clerk(void *args) {
	clerk_t* ck = malloc(sizeof(int));
	ck->id = (long)args;
	
	sem_wait(&semClerk);

	while (true)
	{	
		// MUTEX PARA GARANTIR QUE VALORES NAO IRAO SE REPETIR 
		pthread_mutex_lock(&clerkMutex);

		int val = get_retrieved_ticket(pc);
		
		// LIBERA O CLIENTE PARA FAZER A VERIFICACAO NA FILA DE CHAMADA
		sem_post(&semClientWaitToCall);

		pthread_mutex_unlock(&clerkMutex);

		if(val == -1){
			break;
		}
		
		set_current_ticket(pc,val,ck->id);
		
		order_t *value;

		while(pc->clerks_order_spot[ck->id] == 0){
			// SEMAFORO QUE AGUARDA SUA LIBERACAO QUE VEM DO CLIENTE (client_inform_order()) APOS REALIZAR SEU PEDIDO
			sem_wait(&semClerkWaitToClient);
		}

		value = pc->clerks_order_spot[ck->id];
		
		clerk_annotate_order();
		anounce_clerk_order(value);
		clerk_create_order(value);

		pc->clerks_order_spot[ck->id] = 0;
	}

	// RESPONSAVEL POR GARANTIR QUE TODAS AS THREADS SE ENCERREM CASO A QUANTIDADE DE CLIENTES FOR MENOR QUE A DE FUNCIONARIOS
	if(numClients < numClerks){
		for (int i = 0; i < (numClerks-numClients); i++)
		{
			sem_post(&semClerk);
		}
	}

	return NULL;
}

void* cooker(void *args) {
	int num_plates = 0;

	while (1)
	{
		order_t value;
		
		while (1)
		{
			if(num_plates < cookerOrders.actualSize){
				value = cookerOrders.data[num_plates];
				break;
			}
		}
		
		cooker_wait_cook_time();
		anounce_cooker_order(&value);

		balcao.data[num_plates] = value;
		balcao.actualSize++;
		
		num_plates++;
		pc->lastCheckReady++;

		for (int i = 0; i < pc->clientsWaitingOrder; i++)
		{
			sem_post(&semClient);
		}

		if(num_plates == numClients){
			break;
		}
	}

	return NULL;
}

int main(int argc, char *argv[]) {
	parseArgs(argc, argv);
	pc = init_ticket_caller();

	balcao_init(&balcao);
	cookerOrders_init(&cookerOrders);

	int n_threads_client = atoi(argv[1]);
	int n_threads_clerk = atoi(argv[2]);

	pthread_mutex_init(&clientMutex, NULL);
	pthread_mutex_init(&clerkMutex, NULL);
	pthread_mutex_init(&clientWaitMutex, NULL);

    sem_init(&semClerk,0,0);
    sem_init(&semClient,0,0);
    sem_init(&semClientWaitToCall,0,0);
    sem_init(&semClerkWaitToClient,0,0);

	pthread_t clientsThreads[n_threads_client];
	pthread_t clerkThreads[n_threads_clerk];
	pthread_t cookerThreads;

	for (long int i = 0; i < n_threads_clerk; i++)
    {
        pthread_create(&clerkThreads[i], NULL, clerk, (void *)i);
    }
	for (long int i = 0; i < n_threads_client; i++)
    {
        pthread_create(&clientsThreads[i], NULL, client, (void *)i);
    }

	pthread_create(&cookerThreads, NULL, cooker, NULL);

	for (long int i = 0; i < n_threads_clerk; i++)
    {
        pthread_join(clerkThreads[i], NULL);
    }
	for (long int i = 0; i < n_threads_client; i++)
    {
        pthread_join(clientsThreads[i], NULL);
    }

	pthread_join(cookerThreads, NULL);

	pthread_mutex_destroy(&clientMutex);
	pthread_mutex_destroy(&clerkMutex);
	pthread_mutex_destroy(&clientWaitMutex);

    sem_destroy(&semClerk);
    sem_destroy(&semClient);
    sem_destroy(&semClientWaitToCall);
    sem_destroy(&semClerkWaitToClient);

	return 0;
}