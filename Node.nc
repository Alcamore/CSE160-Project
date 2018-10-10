/*
* ANDES Lab - University of California, Merced
* This class provides the basic functions of a network node.
*
* @author UCM ANDES Lab
* @date   2013/09/03
*
*/
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;

    uses interface Random as Random;

    uses interface FloodingHandler;

    uses interface Timer<TMilli> as NeighborTimer;
    uses interface NeighborDiscoveryHandler;
}

implementation{
    // Global Variables
    pack sendPackage;                   // Generic packet used to hold the next packet to be sent
    uint16_t current_seq = 0;           // Sequence number of packets sent by node

    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    void pingHandler(pack* msg);
    uint16_t randNum(uint16_t min, uint16_t max);

    /**
     * Called when the node is started
     * Initializes/starts necessary services
     */
    event void Boot.booted(){
        call AMControl.start();
        call NeighborTimer.startPeriodic(randNum(1000,2000));

        dbg(GENERAL_CHANNEL, "Booted\n");
    }

    /**
     * Starts radio, called during boot
     */
    event void AMControl.startDone(error_t err){
        if (err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err){}

    /**
     * Helper function for processing ping packets
     * Only protocols needed are ping and ping reply
     */
    // TODO: Move to protocol handler module
    void pingHandler(pack* msg) {
        switch(msg->protocol) {
            case PROTOCOL_PING:
                dbg(GENERAL_CHANNEL, "--- Ping recieved from %d\n", msg->src);
                dbg(GENERAL_CHANNEL, "--- Packet Payload: %s\n", msg->payload);
                dbg(GENERAL_CHANNEL, "--- Sending Reply...\n");
                makePack(&sendPackage, msg->dest, msg->src, MAX_TTL, PROTOCOL_PINGREPLY, current_seq++, (uint8_t*)msg->payload, PACKET_MAX_PAYLOAD_SIZE);
                call FloodingHandler.flood(&sendPackage);
                break;
                    
            case PROTOCOL_PINGREPLY:
                dbg(GENERAL_CHANNEL, "--- Ping reply recieved from %d\n", msg->src);
                break;
                    
            default:
                dbg(GENERAL_CHANNEL, "Unrecognized ping protocol: %d\n", msg->protocol);
        }
    }

    /**
     * Called when a packet is recieved
     * Handles the validation of recieved packets, and identifies the type of packet
     */
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

        if (len == sizeof(pack)) {
            pack* myMsg=(pack*) payload;

            // Check TTL
            if (myMsg->TTL-- == 0) {
                return msg;
            }
            
            // Regular Ping
            if (myMsg->dest == TOS_NODE_ID) {
                pingHandler(myMsg);
                
            // Neighbor Discovery
            } else if (myMsg->dest == AM_BROADCAST_ADDR) {
                call NeighborDiscoveryHandler.recieve(myMsg);

            // Not Destination
            } else {
                call FloodingHandler.flood(myMsg);
            }
            return msg;
        }
        dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

    /**
     * Runs neighbor discovery at a random time between 1 and 2 seconds
     * Neighbor discovery only needs the node's current sequence number
     */
    event void NeighborTimer.fired() {
        call NeighborDiscoveryHandler.discover(current_seq++);
    }

    /**
     * Called when a node is added or removed from the neighbor list
     * Only performs action after a few initial discovery cycles
     */
    event void NeighborDiscoveryHandler.neighborListUpdated() {}

    /**
     * Called when simulation issues a ping command to the node
     */
    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call FloodingHandler.flood(&sendPackage);
    }

    /**
     * Called when simulation issues a command to print the list of neighbor node IDs
     */
    event void CommandHandler.printNeighbors(){
        call NeighborDiscoveryHandler.printNeighbors();
    }

    event void CommandHandler.printRouteTable(){ dbg(GENERAL_CHANNEL, "printRouteTable\n"); }

    event void CommandHandler.printLinkState(){ dbg(GENERAL_CHANNEL, "printLinkState\n"); }

    event void CommandHandler.printDistanceVector(){ dbg(GENERAL_CHANNEL, "printDistanceVector\n"); }

    event void CommandHandler.setTestServer(){ dbg(GENERAL_CHANNEL, "setTestServer\n"); }

    event void CommandHandler.setTestClient(){ dbg(GENERAL_CHANNEL, "setTestClient\n"); }

    event void CommandHandler.setAppServer(){ dbg(GENERAL_CHANNEL, "setAppServer\n"); }

    event void CommandHandler.setAppClient(){ dbg(GENERAL_CHANNEL, "setAppClient\n"); }

    /**
     * Assembles a packet given by the first parameter using the other parameters
     */
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    /**
     * Generates a random 16-bit number between 'min' and 'max'
     */
    uint16_t randNum(uint16_t min, uint16_t max) {
        return ( call Random.rand16() % (max-min+1) ) + min;
    }
}
