import os
import sys
import time
import threading
from tasks import Tasks
from multiprocessing import Process, Pool, Lock
from threading import Thread
from concurrent.futures import ThreadPoolExecutor

numProcessos = int(sys.argv[2])
numthreads = int(sys.argv[3])
puzzles = []
processos = []
mainPidProcess = 0
lock = Lock()

def abertura_do_aquivo(): 
    entradas = open(sys.argv[1])
    ent = entradas.readlines()  ## abertura dos arquivos
    linhaAtual = 0
    linhas = []                 ## vetores de linhas

    for i in ent:
        colunas = []            ## vetores de colunas
        for j in i:
            try:
                colunas.append(int(j))
            except:
                pass

        if len(colunas) != 0:
            linhaAtual += 1
            linhas.append(colunas)

        if linhaAtual%9 == 0 and len(linhas) != 0:
            puzzles.append(linhas)
            linhas = []

    entradas.close()            ## fechamento dos arquivos 

def checkRow(matrixIdx,tasksObj,lockErrors,lockCompleted):
    threadId = threading.get_ident()
    tasksObj.setThreadsIds(threadId)

    for i in tasksObj.tasksRows:
        if tasksObj.tasksRows[i] == None:
            tasksObj.tasksRows[i] == True
            rowIdx = int(i)

    if(sum(puzzles[matrixIdx][rowIdx]) == 45):
        lockCompleted.acquire()
        tasksObj.setCompleted()
        lockCompleted.release()
    else:
        lockErrors.acquire()
        tasksObj.setErrorLogs(threadId,f'linha {rowIdx+1}')
        tasksObj.setError()
        lockErrors.release()

def checkCollum(matrixIdx,tasksObj,lockErrors,lockCompleted):
    sumNumbers = 0
    tempPuzzle = puzzles[matrixIdx]
    threadId = threading.get_ident()
    tasksObj.setThreadsIds(threadId)

    for i in tasksObj.tasksCol:
        if tasksObj.tasksCol[i] == None:
            tasksObj.tasksCol[i] == True
            collumIdx = int(i)

    for i in tempPuzzle:
        sumNumbers += i[collumIdx]
    if sumNumbers == 45:
        lockCompleted.acquire()
        tasksObj.setCompleted()
        lockCompleted.release()
    else:
        lockErrors.acquire()
        tasksObj.setErrorLogs(threadId,f'coluna {collumIdx+1}')
        tasksObj.setError()
        lockErrors.release()

def checkArea(matrixIdx,tasksObj,lockErrors,lockCompleted):
    sumNumbers = 0
    areaStart = tasksObj.getAreas()
    threadId = threading.get_ident()
    tasksObj.setThreadsIds(threadId)

    for i in tasksObj.tasksArea:
        if tasksObj.tasksArea[i] == None:
            tasksObj.tasksArea[i] == True
            areaIdx = int(i)
    
    areaStart = areaStart[areaIdx+1]

    for i in range(areaStart[0],areaStart[0]+3,1):
        for j in range(areaStart[1],areaStart[1]+3,1):
            sumNumbers += puzzles[matrixIdx][i][j]
    
    if sumNumbers == 45:
        lockCompleted.acquire()
        tasksObj.setCompleted()
        lockCompleted.release()
    else:
        lockErrors.acquire()
        tasksObj.setErrorLogs(threadId,f'regiao {areaIdx+1}')
        tasksObj.setError()
        lockErrors.release()

def threadsVerify(matrixIdx,tasksObj):
    threadId = threading.get_ident()

    tasksObj.setThreadsIds(threadId)

    tasks = tasksObj.getTasks()
    
    for i in tasks:
        if tasks[i] == None:
            tasksObj.changeStateTask(i,True)
            name = i.split("-")
            # print(f'thread id -> {threadId} item -> {name} matrix -> {matrixIdx}')
            if name[0] == 'row':
                checkRow(matrixIdx,int(name[1]),tasksObj,threadId,lockErrors,lockCompleted)
            elif name[0] == 'collum':
                checkCollum(matrixIdx,int(name[1]),tasksObj,threadId,lockErrors,lockCompleted)
            else:
                checkArea(matrixIdx,int(name[1]),tasksObj,threadId,lockErrors,lockCompleted)
            return

def processMain(matrixIdx):
    global mainPidProcess
    threads = []
    actualTasks = Tasks(os.getpid() - mainPidProcess,matrixIdx)

    lockErrors = threading.Lock()
    lockCompleted = threading.Lock()

    # for i in range(numthreads):
    #     threads.append(Thread(target=threadsVerify, args=(matrixIdx,actualTasks)))
    
    # for i in range(numthreads):
    #     threads[i].start()

    # for i in range(numthreads):
    #     threads[i].join()

    with ThreadPoolExecutor(max_workers=numthreads) as pool:
        for i in range(9):
            pool.submit(checkRow,matrixIdx,actualTasks,lockErrors,lockCompleted)
            pool.submit(checkCollum,matrixIdx,actualTasks,lockErrors,lockCompleted)
            pool.submit(checkArea,matrixIdx,actualTasks,lockErrors,lockCompleted)
    
    with lock:
        actualTasks.setFinalLog()
    
def setup():

    if(numthreads > 27 or numthreads <= 0):
        print("Numero de threads invalido, o numero de threads deve ser menor ou igual a 27 e maior que 0")
        return
    elif(numProcessos < 1):
        print("Numero de processos invalido, o numero de processos deve ser maior ou igual a 1")
        return

    timestart = time.time()
    global mainPidProcess
    mainPidProcess = os.getpid()

    abertura_do_aquivo()

    with Pool(processes=numProcessos) as pool:
        pool.map(processMain,range(len(puzzles)))
        
    print(time.time() - timestart)
    
setup()