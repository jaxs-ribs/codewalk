export type Events = {
    open: void;
    helloAck: {
        sessionId: string;
    };
    frame: {
        raw: any;
        inner?: any;
    };
    ack: {
        text?: string;
        replyTo?: string;
    };
    peerJoined: {
        role: string;
    };
    peerLeft: {
        role: string;
    };
    sessionKilled: void;
    error: {
        message: string;
    };
};
export type Listener<T> = (ev: T) => void;
export interface Client {
    on<K extends keyof Events>(ev: K, fn: Listener<Events[K]>): void;
    off<K extends keyof Events>(ev: K, fn: Listener<Events[K]>): void;
    sendUserText(text: string): void;
    close(): void;
}
export type WebSocketCtor = new (url: string) => {
    onopen: any;
    onmessage: any;
    onerror: any;
    onclose: any;
    send(data: any): any;
    close(): any;
};
export declare function connect(opts: {
    ws: string;
    sid: string;
    tok: string;
    WebSocket: WebSocketCtor;
}): Client;
