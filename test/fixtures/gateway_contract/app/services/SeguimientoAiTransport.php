<?php
/** Transporte fijo al proveedor: sin destinos configurables ni redirecciones. */
final class SeguimientoAiTransport
{
    const ENDPOINT = 'https://api.openai.com/v1/responses';
    const MAX_RESPONSE_BYTES = 65536;

    /** El callback es un seam de prueba para respuestas sintéticas de servicio. */
    private $sender;

    public function __construct(?callable $sender = null)
    {
        $this->sender = $sender;
    }

    public function request(string $key, array $payload): array
    {
        if ($key === '') throw new RuntimeException('configuration_missing');
        if ($this->sender !== null) {
            $response = call_user_func($this->sender, $key, $payload);
            if (!is_array($response) || !isset($response['status'], $response['body']) ||
                !is_int($response['status']) || !is_string($response['body'])) {
                throw new RuntimeException('provider_unavailable');
            }
            $status = $response['status'];
            $body = $response['body'];
        } else {
            $response = $this->curl($key, $payload);
            $status = $response['status'];
            $body = $response['body'];
        }
        if (strlen($body) > self::MAX_RESPONSE_BYTES) throw new RuntimeException('provider_response_too_large');
        if ($status !== 200) throw new RuntimeException('provider_http_' . $status);
        $decoded = json_decode($body, true);
        if (!is_array($decoded)) throw new RuntimeException('provider_invalid_json');
        return $decoded;
    }

    private function curl(string $key, array $payload): array
    {
        $curl = curl_init(self::ENDPOINT);
        if (!$curl) throw new RuntimeException('provider_unavailable');
        $response = '';
        curl_setopt_array($curl, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Authorization: Bearer ' . $key],
            CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE),
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_TIMEOUT => 40,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_WRITEFUNCTION => static function ($ch, string $chunk) use (&$response): int {
                if (strlen($response) + strlen($chunk) > self::MAX_RESPONSE_BYTES) return 0;
                $response .= $chunk;
                return strlen($chunk);
            },
        ]);
        try {
            $ok = curl_exec($curl);
            $status = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
            if ($ok === false) throw new RuntimeException('provider_unavailable');
        } finally {
            curl_close($curl);
        }
        return ['status' => $status, 'body' => $response];
    }
}
