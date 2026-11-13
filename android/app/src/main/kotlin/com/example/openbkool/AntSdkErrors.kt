package com.example.openbkool

import com.dsi.ant.channel.AntCommandFailedException
import com.dsi.ant.channel.ChannelNotAvailableException

internal fun antErrorDetails(error: Exception): Map<String, Any?> {
    val details = linkedMapOf<String, Any?>(
        "type" to error.javaClass.name, "message" to error.message,
        "stackTrace" to error.stackTraceToString(),
        "causes" to generateSequence(error.cause) { it.cause }.take(5).map {
            mapOf("type" to it.javaClass.name, "message" to it.message)
        }.toList(),
    )
    if (error is AntCommandFailedException) {
        details["failureReason"] = runCatching { error.failureReason?.name }.getOrNull()
        details["failureReasonCode"] = runCatching { error.failureReason?.rawValue }.getOrNull()
        details["attemptedMessageType"] = runCatching { error.attemptedMessageType?.name }.getOrNull()
        details["attemptedMessageId"] = runCatching { error.attemptedMessageType?.messageId }.getOrNull()
        details["antMessage"] = runCatching { error.antMessage?.let {
            mapOf("messageId" to it.messageId, "contentHex" to hex(it.messageContent))
        } }.getOrNull()
        details["responseMessage"] = runCatching { error.responseMessage?.let {
            mapOf("initiatingMessageId" to it.initiatingMessageId, "responseCode" to it.rawResponseCode,
                "responseName" to it.responseCode?.name, "contentHex" to hex(it.messageContent))
        } }.getOrNull()
    }
    if (error is ChannelNotAvailableException) {
        details["channelUnavailableReason"] = error.reasonCode.name
        details["channelUnavailableCode"] = error.reasonCode.rawValue
    }
    return details
}
